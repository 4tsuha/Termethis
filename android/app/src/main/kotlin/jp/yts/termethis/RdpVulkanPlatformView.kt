package jp.yts.termethis

import android.content.Context
import android.graphics.PixelFormat
import android.view.MotionEvent
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

internal const val RDP_VULKAN_VIEW_TYPE = "jp.yts.termethis/rdp_vulkan"

internal object RdpVulkanBridge {
    private val loaded = runCatching {
        System.loadLibrary("termethis_core")
        true
    }.getOrDefault(false)

    external fun nativeAttachSurface(
        sessionId: Long,
        surface: Surface,
        width: Int,
        height: Int,
    ): Boolean

    external fun nativeDetachSurface(sessionId: Long)

    external fun nativeMouse(
        sessionId: Long,
        x: Float,
        y: Float,
        button: Int,
        pressed: Boolean,
    ): Boolean

    fun isLoaded(): Boolean = loaded
}

internal class RdpVulkanViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        RdpVulkanPlatformView(
            context = context,
            messenger = messenger,
            viewId = viewId,
            creationArguments = args as? Map<*, *> ?: emptyMap<String, Any>(),
        )
}

private class RdpVulkanPlatformView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    creationArguments: Map<*, *>,
) : PlatformView, SurfaceHolder.Callback, View.OnTouchListener, MethodChannel.MethodCallHandler {
    private val sessionId = (creationArguments["sessionId"] as? Number)?.toLong() ?: -1L
    private val channel = MethodChannel(messenger, "$RDP_VULKAN_VIEW_TYPE/$viewId")
    private var disposed = false
    private var lastMoveNanos = 0L
    private var surfaceAttached = false
    private var attachedWidth = 0
    private var attachedHeight = 0

    private val surfaceView = SurfaceView(context).apply {
        holder.setFormat(PixelFormat.OPAQUE)
        holder.addCallback(this@RdpVulkanPlatformView)
        setBackgroundColor(android.graphics.Color.BLACK)
        isFocusable = true
        isFocusableInTouchMode = true
        setOnTouchListener(this@RdpVulkanPlatformView)
    }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = surfaceView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                if (!RdpVulkanBridge.isLoaded()) {
                    result.error(
                        "native_library_unavailable",
                        "Termethis native Vulkan library is unavailable",
                        null,
                    )
                } else if (sessionId <= 0) {
                    result.error("invalid_session", "RDP session ID is invalid", null)
                } else {
                    result.success(mapOf("renderer" to "native Vulkan Surface"))
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) = Unit

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        if (disposed || sessionId <= 0 || !RdpVulkanBridge.isLoaded()) return
        if (surfaceAttached && attachedWidth == width && attachedHeight == height) return
        surfaceAttached = RdpVulkanBridge.nativeAttachSurface(
            sessionId = sessionId,
            surface = holder.surface,
            width = width,
            height = height,
        )
        if (surfaceAttached) {
            attachedWidth = width
            attachedHeight = height
        }
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        surfaceAttached = false
        attachedWidth = 0
        attachedHeight = 0
        if (sessionId > 0 && RdpVulkanBridge.isLoaded()) {
            RdpVulkanBridge.nativeDetachSurface(sessionId)
        }
    }

    override fun onTouch(view: View, event: MotionEvent): Boolean {
        if (disposed || sessionId <= 0 || !RdpVulkanBridge.isLoaded()) return false
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                view.requestFocus()
                RdpVulkanBridge.nativeMouse(sessionId, event.x, event.y, 1, true)
            }
            MotionEvent.ACTION_MOVE -> {
                val now = event.eventTime * 1_000_000L
                if (now - lastMoveNanos >= POINTER_MOVE_INTERVAL_NANOS) {
                    lastMoveNanos = now
                    RdpVulkanBridge.nativeMouse(sessionId, event.x, event.y, 0, false)
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL ->
                RdpVulkanBridge.nativeMouse(sessionId, event.x, event.y, 1, false)
            else -> return false
        }
        return true
    }

    override fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        surfaceView.holder.removeCallback(this)
        surfaceView.setOnTouchListener(null)
        if (sessionId > 0 && RdpVulkanBridge.isLoaded()) {
            RdpVulkanBridge.nativeDetachSurface(sessionId)
        }
    }

    private companion object {
        const val POINTER_MOVE_INTERVAL_NANOS = 8_000_000L
    }
}
