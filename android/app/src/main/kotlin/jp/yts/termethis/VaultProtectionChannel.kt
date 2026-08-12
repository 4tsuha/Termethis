package jp.yts.termethis

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.CancellationSignal
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

class VaultProtectionChannel(
    private val activity: FlutterActivity,
    messenger: BinaryMessenger,
) {
    companion object {
        private const val CHANNEL = "jp.yts.termethis/vault_protection"
        private const val KEY_ALIAS_PREFIX = "termethis.vault.protection."
        private const val BIOMETRIC_STRONG = BiometricManager.Authenticators.BIOMETRIC_STRONG
        private const val DEVICE_CREDENTIAL = BiometricManager.Authenticators.DEVICE_CREDENTIAL
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val biometricManager = activity.getSystemService(BiometricManager::class.java)
    private val keyguardManager = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
    private var locked = true
    private var unlockedUntilMillis = 0L
    private var oneTimeUnlockAvailable = false
    private var prompt: BiometricPrompt? = null
    private var cancellationSignal: CancellationSignal? = null

    init {
        channel.setMethodCallHandler { call, result ->
            val mode = call.argument<String>("mode") ?: "none"
            when (call.method) {
                "status" -> result.success(status(mode))
                "configure" -> runCatching {
                    if (mode != "none") ensureKey(mode)
                    locked = mode != "none"
                    unlockedUntilMillis = 0L
                    oneTimeUnlockAvailable = false
                }.fold({ result.success(null) }, { result.error("configureFailed", null, null) })
                "unlock" -> authenticate(mode, result)
                "lock" -> {
                    locked = true
                    unlockedUntilMillis = 0L
                    oneTimeUnlockAvailable = false
                    cancellationSignal?.cancel()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        cancellationSignal?.cancel()
        oneTimeUnlockAvailable = false
        prompt = null
        channel.setMethodCallHandler(null)
    }

    private fun status(mode: String): Map<String, Any> {
        if (mode == "none") {
            return mapOf(
                "available" to true,
                "deviceCredentialAvailable" to keyguardManager.isDeviceSecure,
                "strongBiometricAvailable" to canUseStrongBiometric(),
                "locked" to false,
                "keyInvalidated" to false,
            )
        }
        val invalidated = runCatching { ensureKey(mode); false }
            .getOrElse { it is KeyPermanentlyInvalidatedException }
        val validity = validitySeconds(mode)
        val oneTimeMode = mode == "everyUnlock"
        val canUseOnce = oneTimeMode && oneTimeUnlockAvailable
        val expired = validity > 0 && System.currentTimeMillis() >= unlockedUntilMillis
        val isLocked = if (oneTimeMode) !canUseOnce else locked || expired
        if (canUseOnce) {
            oneTimeUnlockAvailable = false
            locked = true
        }
        return mapOf(
            "available" to (keyguardManager.isDeviceSecure || canUseStrongBiometric()),
            "deviceCredentialAvailable" to keyguardManager.isDeviceSecure,
            "strongBiometricAvailable" to canUseStrongBiometric(),
            "locked" to isLocked,
            "keyInvalidated" to invalidated,
        )
    }

    private fun authenticate(mode: String, result: MethodChannel.Result) {
        if (mode == "none") {
            locked = false
            result.success("unlocked")
            return
        }
        if (!keyguardManager.isDeviceSecure && !canUseStrongBiometric()) {
            result.success("unavailable")
            return
        }
        runCatching { ensureKey(mode) }.onFailure {
            result.success(if (it is KeyPermanentlyInvalidatedException) "keyInvalidated" else "unavailable")
            return
        }
        val authenticators = allowedAuthenticators()
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                if (!verifyKeyUse(mode)) {
                    result.success("keyInvalidated")
                    return
                }
                locked = false
                val seconds = validitySeconds(mode)
                oneTimeUnlockAvailable = mode == "everyUnlock"
                unlockedUntilMillis = if (seconds == 0) 0L else
                    System.currentTimeMillis() + seconds * 1000L
                result.success("unlocked")
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                val canceled = errorCode == BiometricPrompt.BIOMETRIC_ERROR_CANCELED ||
                    errorCode == BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED
                result.success(if (canceled) "canceled" else "unavailable")
            }
        }
        prompt = BiometricPrompt.Builder(activity)
            .setTitle("Vaultを解錠")
            .setDescription("保存したSSH認証情報を使用します")
            .setAllowedAuthenticators(authenticators)
            .build()
        cancellationSignal = CancellationSignal()
        prompt?.authenticate(
            cancellationSignal!!,
            activity.mainExecutor,
            callback,
        )
    }

    private fun canUseStrongBiometric(): Boolean =
        biometricManager.canAuthenticate(BIOMETRIC_STRONG) == BiometricManager.BIOMETRIC_SUCCESS

    private fun allowedAuthenticators(): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return BIOMETRIC_STRONG or DEVICE_CREDENTIAL
        }
        return if (canUseStrongBiometric()) BIOMETRIC_STRONG else DEVICE_CREDENTIAL
    }

    private fun validitySeconds(mode: String): Int = when (mode) {
        "fiveMinutes" -> 300
        "thirtySeconds" -> 30
        else -> 0
    }

    private fun ensureKey(mode: String): SecretKey {
        val alias = KEY_ALIAS_PREFIX + mode
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        val spec = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setUserAuthenticationRequired(true)
            .apply {
                val validity = validitySeconds(mode)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    setUserAuthenticationParameters(
                        validity.coerceAtLeast(1),
                        KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    setUserAuthenticationValidityDurationSeconds(if (validity == 0) 1 else validity)
                }
            }
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            .apply { init(spec) }
            .generateKey()
    }

    private fun verifyKeyUse(mode: String): Boolean = try {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, ensureKey(mode))
        cipher.doFinal(byteArrayOf(0x54, 0x4d))
        true
    } catch (_: Exception) {
        false
    }
}
