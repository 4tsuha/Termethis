package jp.hgzt23678.ssh_terminal_ja

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.content.res.Configuration
import android.content.pm.PackageManager
import android.os.Build
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val PRIVATE_KEY_CHANNEL =
            "jp.hgzt23678.ssh_terminal_ja/private_key_picker"
        private const val PRIVATE_KEY_REQUEST_CODE = 4107
        private const val MAXIMUM_PRIVATE_KEY_BYTES = 1024 * 1024
        private const val DISPLAY_PERFORMANCE_CHANNEL =
            "jp.hgzt23678.ssh_terminal_ja/display_performance"
        private const val BACKGROUND_SESSION_CHANNEL =
            "jp.hgzt23678.ssh_terminal_ja/background_session"
        private const val TERMINAL_WINDOW_CHANNEL =
            "jp.hgzt23678.ssh_terminal_ja/terminal_window"
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 4109
    }

    private val refreshRateController = DisplayRefreshRateController()
    private var pendingPrivateKeyResult: MethodChannel.Result? = null
    private var pendingBackgroundSessionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRIVATE_KEY_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "pickPrivateKey") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingPrivateKeyResult != null) {
                    result.error("picker_busy", "Private key picker is already open", null)
                    return@setMethodCallHandler
                }
                pendingPrivateKeyResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                }
                startActivityForResult(intent, PRIVATE_KEY_REQUEST_CODE)
            }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DISPLAY_PERFORMANCE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setMode" -> {
                    refreshRateController.setMode(
                        this,
                        call.argument<String>("mode"),
                    )
                    result.success(null)
                }
                "pulseHigh" -> {
                    refreshRateController.pulseHigh(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKGROUND_SESSION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "setRunning") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val running = call.argument<Boolean>("running") == true
            if (!running) {
                stopService(Intent(this, SshKeepAliveService::class.java))
                result.success(null)
                return@setMethodCallHandler
            }
            startBackgroundSessionService(result)
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TERMINAL_WINDOW_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "apply") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val keepAwake = call.argument<Boolean>("keepScreenAwake") == true
            val resizeForKeyboard = call.argument<Boolean>("resizeForKeyboard") == true
            if (keepAwake) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
            window.setSoftInputMode(
                if (resizeForKeyboard) {
                    WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
                } else {
                    WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING
                },
            )
            result.success(null)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.post { refreshRateController.attachTo(this) }
    }

    override fun onResume() {
        super.onResume()
        window.decorView.post { refreshRateController.attachTo(this) }
    }

    override fun onMultiWindowModeChanged(
        isInMultiWindowMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
        window.decorView.post { refreshRateController.attachTo(this) }
    }

    override fun onDestroy() {
        pendingBackgroundSessionResult?.error(
            "activity_destroyed",
            "Activity was destroyed before notification permission completed",
            null,
        )
        pendingBackgroundSessionResult = null
        refreshRateController.detach()
        super.onDestroy()
    }

    @Deprecated("Deprecated in Android SDK, retained for FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PRIVATE_KEY_REQUEST_CODE) {
            return
        }
        val result = pendingPrivateKeyResult ?: return
        pendingPrivateKeyResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }

        val uri = data.data!!
        try {
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    output.write(buffer, 0, count)
                    if (output.size() > MAXIMUM_PRIVATE_KEY_BYTES) {
                        result.error("key_too_large", "Private key exceeds size limit", null)
                        return
                    }
                }
                output.toByteArray()
            } ?: run {
                result.error("key_read_failed", "Unable to open private key", null)
                return
            }
            result.success(
                mapOf(
                    "name" to displayName(uri),
                    "bytes" to bytes,
                ),
            )
        } catch (error: Exception) {
            result.error("key_read_failed", "Unable to read private key", null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST_CODE) return
        val result = pendingBackgroundSessionResult ?: return
        pendingBackgroundSessionResult = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startBackgroundSessionService(result)
        } else {
            result.error(
                "notification_permission_denied",
                "Notification permission is required for background sessions",
                null,
            )
        }
    }

    private fun startBackgroundSessionService(result: MethodChannel.Result) {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingBackgroundSessionResult != null) {
                result.error("permission_busy", "Notification permission is pending", null)
                return
            }
            pendingBackgroundSessionResult = result
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST_CODE,
            )
            return
        }
        val intent = Intent(this, SshKeepAliveService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        result.success(null)
    }

    private fun displayName(uri: android.net.Uri): String {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) {
                    return cursor.getString(index)
                }
            }
        }
        return uri.lastPathSegment ?: "private_key"
    }
}
