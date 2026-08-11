package jp.yts.termethis

import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import rikka.shizuku.Shizuku

class ShizukuDiagnosticsChannel(
    context: Context,
    messenger: BinaryMessenger,
) {
    companion object {
        private const val CHANNEL_NAME = "jp.yts.termethis/shizuku_diagnostics"
        private const val PERMISSION_REQUEST_CODE = 4111
        private const val USER_SERVICE_VERSION = 1
        private const val BIND_TIMEOUT_MILLIS = 10_000L
    }

    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val remoteExecutor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "termethis-shizuku-ipc").apply { isDaemon = true }
    }
    private val userServiceArgs = Shizuku.UserServiceArgs(
        ComponentName(context.packageName, DiagnosticsUserService::class.java.name),
    )
        .daemon(false)
        .processNameSuffix("diagnostics")
        .version(USER_SERVICE_VERSION)
        .tag("termethis-diagnostics")

    @Volatile
    private var service: IDiagnosticsUserService? = null
    private var binding = false
    private var disposed = false
    private var pendingPermissionResult: MethodChannel.Result? = null
    private data class PendingRemoteOperation(
        val result: MethodChannel.Result,
        val execute: (IDiagnosticsUserService) -> Unit,
    )

    private val pendingServiceOperations = mutableListOf<PendingRemoteOperation>()

    private val bindTimeout = Runnable {
        if (!binding) return@Runnable
        binding = false
        failPending("service_bind_timeout", "Shizuku UserService did not respond")
    }

    private val permissionListener =
        Shizuku.OnRequestPermissionResultListener { requestCode, _ ->
            if (requestCode != PERMISSION_REQUEST_CODE) return@OnRequestPermissionResultListener
            val result = pendingPermissionResult ?: return@OnRequestPermissionResultListener
            pendingPermissionResult = null
            result.success(statusMap())
        }

    private val binderDeadListener = Shizuku.OnBinderDeadListener {
        service = null
        binding = false
        pendingPermissionResult?.error(
            "shizuku_unavailable",
            "Shizuku service stopped during permission request",
            null,
        )
        pendingPermissionResult = null
        failPending("shizuku_unavailable", "Shizuku service stopped")
    }

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            mainHandler.removeCallbacks(bindTimeout)
            binding = false
            if (!binder.pingBinder()) {
                failPending("service_bind_failed", "Shizuku UserService binder is unavailable")
                return
            }
            val connectedService = IDiagnosticsUserService.Stub.asInterface(binder)
            service = connectedService
            val operations = pendingServiceOperations.toList()
            pendingServiceOperations.clear()
            operations.forEach { it.execute(connectedService) }
        }

        override fun onServiceDisconnected(name: ComponentName) {
            service = null
        }
    }

    init {
        Shizuku.addRequestPermissionResultListener(permissionListener)
        Shizuku.addBinderDeadListener(binderDeadListener)
        channel.setMethodCallHandler(::handleMethodCall)
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        Shizuku.removeRequestPermissionResultListener(permissionListener)
        Shizuku.removeBinderDeadListener(binderDeadListener)
        pendingPermissionResult?.error(
            "activity_destroyed",
            "Activity was destroyed before Shizuku permission completed",
            null,
        )
        pendingPermissionResult = null
        failPending("activity_destroyed", "Activity was destroyed")
        mainHandler.removeCallbacks(bindTimeout)
        if (service != null || binding) {
            runCatching { Shizuku.unbindUserService(userServiceArgs, serviceConnection, true) }
        }
        service = null
        remoteExecutor.shutdownNow()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> result.success(statusMap())
            "requestPermission" -> requestPermission(result)
            "startLogcatCapture" -> withService(result) { remote ->
                remote.startLogcatCapture(call.argument<Int>("maxLines") ?: 2_000)
            }
            "stopLogcatCapture" -> withConnectedService(result, false) { remote ->
                remote.stopLogcatCapture()
                true
            }
            "isLogcatCapturing" -> withConnectedService(result, false) {
                it.isLogcatCapturing
            }
            "getRecentLogcatLines" -> withConnectedService(result, emptyList<String>()) {
                it.getRecentLogcatLines(call.argument<Int>("limit") ?: 200)
            }
            "clearLogcatCapture" -> withConnectedService(result, false) { remote ->
                remote.clearLogcatCapture()
                true
            }
            "startShell" -> withService(result) { it.startShell() }
            "writeShellInput" -> {
                val input = call.argument<ByteArray>("input")
                if (input == null) {
                    result.error("invalid_request", "Shell input is required", null)
                } else {
                    withConnectedService(result, false) { it.writeShellInput(input) }
                }
            }
            "readShellOutput" -> withConnectedService(result, ByteArray(0)) {
                it.readShellOutput(call.argument<Int>("maxBytes") ?: 64 * 1024)
            }
            "isShellRunning" -> withConnectedService(result, false) { it.isShellRunning }
            "stopShell" -> withConnectedService(result, false) { remote ->
                remote.stopShell()
                true
            }
            else -> result.notImplemented()
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (!isBinderReady()) {
            result.error("shizuku_unavailable", "Shizuku service is not running", null)
            return
        }
        if (runCatching { Shizuku.isPreV11() }.getOrDefault(true)) {
            result.error("shizuku_unsupported", "Shizuku v11 or newer is required", null)
            return
        }
        if (permissionGranted()) {
            result.success(statusMap())
            return
        }
        if (runCatching { Shizuku.shouldShowRequestPermissionRationale() }.getOrDefault(false)) {
            result.error(
                "permission_denied_permanently",
                "Shizuku permission must be enabled from the Shizuku app",
                null,
            )
            return
        }
        if (pendingPermissionResult != null) {
            result.error("permission_busy", "Shizuku permission request is already open", null)
            return
        }
        pendingPermissionResult = result
        try {
            Shizuku.requestPermission(PERMISSION_REQUEST_CODE)
        } catch (error: RuntimeException) {
            pendingPermissionResult = null
            result.error("permission_request_failed", error.message, null)
        }
    }

    private fun <T> withService(
        result: MethodChannel.Result,
        operation: (IDiagnosticsUserService) -> T,
    ) {
        if (!validateAccess(result)) return
        val task: (IDiagnosticsUserService) -> Unit = { remote ->
            executeRemote(result) { operation(remote) }
        }
        val connected = service
        if (connected != null && connected.asBinder().pingBinder()) {
            task(connected)
            return
        }
        service = null
        if (pendingServiceOperations.size >= 8) {
            result.error("service_busy", "Too many pending Shizuku operations", null)
            return
        }
        pendingServiceOperations += PendingRemoteOperation(result, task)
        if (binding) return
        binding = true
        mainHandler.postDelayed(bindTimeout, BIND_TIMEOUT_MILLIS)
        try {
            Shizuku.bindUserService(userServiceArgs, serviceConnection)
        } catch (error: RuntimeException) {
            mainHandler.removeCallbacks(bindTimeout)
            binding = false
            failPending("service_bind_failed", error.message ?: "Unable to bind Shizuku UserService")
        }
    }

    private fun <T> withConnectedService(
        result: MethodChannel.Result,
        disconnectedValue: T,
        operation: (IDiagnosticsUserService) -> T,
    ) {
        val connected = service
        if (connected == null || !connected.asBinder().pingBinder()) {
            service = null
            result.success(disconnectedValue)
            return
        }
        executeRemote(result) { operation(connected) }
    }

    private fun <T> executeRemote(result: MethodChannel.Result, operation: () -> T) {
        remoteExecutor.execute {
            try {
                val value = operation()
                mainHandler.post { result.success(value) }
            } catch (error: Exception) {
                service = null
                mainHandler.post {
                    result.error(
                        "shizuku_remote_error",
                        error.message ?: "Shizuku operation failed",
                        null,
                    )
                }
            }
        }
    }

    private fun validateAccess(result: MethodChannel.Result): Boolean {
        if (!isBinderReady()) {
            result.error("shizuku_unavailable", "Shizuku service is not running", null)
            return false
        }
        if (runCatching { Shizuku.isPreV11() }.getOrDefault(true)) {
            result.error("shizuku_unsupported", "Shizuku v11 or newer is required", null)
            return false
        }
        if (!permissionGranted()) {
            result.error("permission_denied", "Shizuku permission has not been granted", null)
            return false
        }
        return true
    }

    private fun statusMap(): Map<String, Any?> {
        val ready = isBinderReady()
        val preV11 = ready && runCatching { Shizuku.isPreV11() }.getOrDefault(true)
        val granted = ready && !preV11 && permissionGranted()
        val rationale = ready && !granted &&
            runCatching { Shizuku.shouldShowRequestPermissionRationale() }.getOrDefault(false)
        val permission = when {
            !ready -> "unavailable"
            preV11 -> "unsupported"
            granted -> "granted"
            rationale -> "deniedPermanently"
            else -> "denied"
        }
        return mapOf(
            "binderReady" to ready,
            "permission" to permission,
            "serverVersion" to if (ready) runCatching { Shizuku.getVersion() }.getOrNull() else null,
            "serverUid" to if (ready) runCatching { Shizuku.getUid() }.getOrNull() else null,
            "userServiceConnected" to (service?.asBinder()?.pingBinder() == true),
            "shellPtySupported" to false,
            "shellTransport" to "pipes",
        )
    }

    private fun permissionGranted(): Boolean = runCatching {
        Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    }.getOrDefault(false)

    private fun isBinderReady(): Boolean = runCatching { Shizuku.pingBinder() }.getOrDefault(false)

    private fun failPending(code: String, message: String) {
        val operations = pendingServiceOperations.toList()
        pendingServiceOperations.clear()
        operations.forEach { it.result.error(code, message, null) }
    }
}
