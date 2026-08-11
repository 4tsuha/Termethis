package jp.yts.termethis

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.view.Display
import android.view.SurfaceView
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import io.flutter.embedding.android.FlutterView

class DisplayRefreshRateController {
    enum class Mode {
        ADAPTIVE,
        BALANCED,
        MAXIMUM,
    }

    companion object {
        private const val HIGH_RATE_PULSE_MILLIS = 750L
    }

    private val handler = Handler(Looper.getMainLooper())
    private var mode = Mode.ADAPTIVE
    private var activity: Activity? = null
    private var powerSaveReceiver: BroadcastReceiver? = null
    private var powerManager: PowerManager? = null
    private var thermalListener: PowerManager.OnThermalStatusChangedListener? = null
    private val resetPulse = Runnable { applyBasePolicy() }

    fun attachTo(activity: Activity) {
        this.activity = activity
        registerConstraintListeners(activity)
        applyBasePolicy()
    }

    fun setMode(activity: Activity, value: String?) {
        mode = when (value) {
            "balanced" -> Mode.BALANCED
            "maximum" -> Mode.MAXIMUM
            else -> Mode.ADAPTIVE
        }
        attachTo(activity)
    }

    fun pulseHigh(activity: Activity) {
        this.activity = activity
        if (isSystemConstrained(activity)) {
            applyBasePolicy()
            return
        }
        if (mode == Mode.MAXIMUM) return
        handler.removeCallbacks(resetPulse)
        applyRequestedRate(high = true)
        handler.postDelayed(resetPulse, HIGH_RATE_PULSE_MILLIS)
    }

    fun detach() {
        handler.removeCallbacks(resetPulse)
        powerSaveReceiver?.let { receiver ->
            activity?.applicationContext?.unregisterReceiver(receiver)
        }
        powerSaveReceiver = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            thermalListener?.let { listener ->
                powerManager?.removeThermalStatusListener(listener)
            }
        }
        thermalListener = null
        powerManager = null
        activity = null
    }

    private fun applyBasePolicy() {
        val activity = activity ?: return
        handler.removeCallbacks(resetPulse)
        val constrained = isSystemConstrained(activity)
        val attributes = activity.window.attributes
        attributes.preferredDisplayModeId = 0
        attributes.preferredRefreshRate = when {
            constrained -> 0f
            mode == Mode.MAXIMUM -> findFastestRate(activity.window.decorView.display) ?: 0f
            Build.VERSION.SDK_INT < Build.VERSION_CODES.BAKLAVA &&
                mode == Mode.BALANCED -> findNormalRate(activity.window.decorView.display)
            else -> 0f
        }
        activity.window.attributes = attributes

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            activity.window.setFrameRateBoostOnTouchEnabled(true)
            activity.window.setFrameRatePowerSavingsBalanced(
                constrained || mode != Mode.MAXIMUM,
            )
        }
        applyRequestedRate(high = false)
    }

    private fun applyRequestedRate(high: Boolean) {
        val activity = activity ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
            val requestedCategory = when {
                isSystemConstrained(activity) -> View.REQUESTED_FRAME_RATE_CATEGORY_DEFAULT
                high || mode == Mode.MAXIMUM -> View.REQUESTED_FRAME_RATE_CATEGORY_HIGH
                mode == Mode.BALANCED -> View.REQUESTED_FRAME_RATE_CATEGORY_NORMAL
                else -> View.REQUESTED_FRAME_RATE_CATEGORY_DEFAULT
            }
            activity.window.decorView.requestedFrameRate = requestedCategory
            applyRequestedRateToRenderViews(activity.window.decorView, requestedCategory)
            return
        }

        if (high) {
            val display = activity.window.decorView.display ?: return
            val attributes = activity.window.attributes
            attributes.preferredRefreshRate = findFastestRate(display) ?: return
            activity.window.attributes = attributes
        }
    }

    private fun isSystemConstrained(activity: Activity): Boolean {
        val powerManager = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
        val thermalLimited = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            powerManager.currentThermalStatus >= PowerManager.THERMAL_STATUS_SEVERE
        return powerManager.isPowerSaveMode || thermalLimited || activity.isInMultiWindowMode
    }

    private fun registerConstraintListeners(activity: Activity) {
        if (powerSaveReceiver == null) {
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    handler.post { applyBasePolicy() }
                }
            }
            activity.applicationContext.registerReceiver(
                receiver,
                IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED),
            )
            powerSaveReceiver = receiver
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && thermalListener == null) {
            val manager = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
            val listener = PowerManager.OnThermalStatusChangedListener {
                handler.post { applyBasePolicy() }
            }
            manager.addThermalStatusListener(activity.mainExecutor, listener)
            powerManager = manager
            thermalListener = listener
        }
    }

    private fun findFastestRate(display: Display?): Float? {
        display ?: return null
        val currentMode = display.mode
        return display.supportedModes
            .asSequence()
            .filter { candidate ->
                candidate.physicalWidth == currentMode.physicalWidth &&
                    candidate.physicalHeight == currentMode.physicalHeight
            }
            .maxOfOrNull(Display.Mode::getRefreshRate)
    }

    private fun findNormalRate(display: Display?): Float {
        display ?: return 60f
        return display.supportedModes
            .asSequence()
            .map(Display.Mode::getRefreshRate)
            .minByOrNull { rate -> kotlin.math.abs(rate - 60f) }
            ?: 60f
    }

    private fun applyRequestedRateToRenderViews(view: View, requestedCategory: Float) {
        if (view is FlutterView || view is WebView || view is SurfaceView || view is TextureView) {
            view.requestedFrameRate = requestedCategory
        }
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                applyRequestedRateToRenderViews(view.getChildAt(index), requestedCategory)
            }
        }
    }
}
