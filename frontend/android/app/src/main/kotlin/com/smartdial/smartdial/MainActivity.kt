package com.smartdial.smartdial

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * MainActivity
 *
 * Wires the Flutter engine to TelecomChannel so Flutter can:
 *  - Query / request the default dialer role
 *  - Enumerate available SIM / PhoneAccounts
 *  - Trigger a real cellular call via Android TelecomManager
 *  - Receive live call-state events from SmartDialInCallService
 *
 * No WebRTC, no VoIP, no SDP.  Voice travels via the SIM/carrier network.
 */
class MainActivity : FlutterActivity() {

    companion object {
        const val REQUEST_DEFAULT_DIALER = 1001
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        TelecomChannel.register(flutterEngine, this)
    }

    /** Called after the system role-selection UI completes. */
    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_DEFAULT_DIALER) {
            // Flutter will query isDefaultDialer() after the role dialog.
            // No explicit callback needed — Flutter polls on resume.
        }
    }
}
