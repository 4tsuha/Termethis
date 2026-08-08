package jp.hgzt23678.ssh_terminal_ja

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private val refreshRateController = DisplayRefreshRateController()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.post { refreshRateController.applyTo(this) }
    }

    override fun onResume() {
        super.onResume()
        window.decorView.post { refreshRateController.applyTo(this) }
    }
}
