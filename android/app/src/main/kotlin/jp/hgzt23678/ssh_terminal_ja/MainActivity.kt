package jp.hgzt23678.ssh_terminal_ja

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.provider.OpenableColumns
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
    }

    private val refreshRateController = DisplayRefreshRateController()
    private var pendingPrivateKeyResult: MethodChannel.Result? = null

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
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.post { refreshRateController.applyTo(this) }
    }

    override fun onResume() {
        super.onResume()
        window.decorView.post { refreshRateController.applyTo(this) }
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
