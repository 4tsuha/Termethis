package jp.hgzt23678.ssh_terminal_ja

import android.app.Activity
import android.os.Build
import android.view.Display

class DisplayRefreshRateController {
    fun applyTo(activity: Activity) {
        val display = activity.window.decorView.display ?: return
        val preferredRate = findFastestRate(display) ?: return
        val attributes = activity.window.attributes

        attributes.preferredDisplayModeId = 0
        attributes.preferredRefreshRate = preferredRate
        activity.window.attributes = attributes

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            activity.window.setFrameRateBoostOnTouchEnabled(true)
        }
    }

    private fun findFastestRate(display: Display): Float? {
        val currentMode = display.mode
        return display.supportedModes
            .asSequence()
            .filter { mode ->
                mode.physicalWidth == currentMode.physicalWidth &&
                    mode.physicalHeight == currentMode.physicalHeight
            }
            .maxOfOrNull(Display.Mode::getRefreshRate)
    }
}
