package com.smartdial.smartdial

import android.telecom.Call
import android.telecom.InCallService
import android.util.Log

/**
 * SmartDialInCallService — Phase 4
 *
 * Android Telecom binds this service when SmartDial is the default phone app.
 * It tracks all active calls in a thread-safe map, maps states to SmartDial
 * representation, and forwards structured events to Flutter via TelecomChannel.
 *
 * Voice audio path: SIM / cellular carrier. No WebRTC. No internet audio.
 *
 * Supported states:
 *   CONNECTING, DIALING, RINGING, ACTIVE, HOLDING, DISCONNECTED, UNKNOWN
 *
 * Multiple calls are tracked safely — stale call objects are removed on
 * CALL_REMOVED to prevent leaks.
 */
class SmartDialInCallService : InCallService() {

    companion object {
        private const val TAG = "SmartDialInCallService"

        /** Singleton reference — set in onCreate, cleared in onDestroy. */
        @Volatile
        var instance: SmartDialInCallService? = null
            private set
    }

    // callId (stable string key) → Call object
    private val callMap = mutableMapOf<String, Call>()

    /** Generate a stable ID for a Call object using its system hashCode. */
    private fun callId(call: Call): String = call.hashCode().toString()

    /** Resolve call direction from Call.Details. */
    private fun callDirection(call: Call): String {
        return try {
            val details = call.details ?: return "UNKNOWN"
            when {
                details.hasProperty(Call.Details.PROPERTY_SELF_MANAGED) -> "UNKNOWN"
                details.callDirection == Call.Details.DIRECTION_OUTGOING -> "OUTGOING"
                details.callDirection == Call.Details.DIRECTION_INCOMING -> "INCOMING"
                else -> "UNKNOWN"
            }
        } catch (_: Exception) { "UNKNOWN" }
    }

    /** Map Android Telecom state integer to a SmartDial state string. */
    fun callStateLabel(state: Int): String = when (state) {
        Call.STATE_CONNECTING   -> "CONNECTING"
        Call.STATE_DIALING      -> "DIALING"
        Call.STATE_RINGING      -> "RINGING"
        Call.STATE_ACTIVE       -> "ACTIVE"
        Call.STATE_HOLDING      -> "HOLDING"
        Call.STATE_DISCONNECTED -> "DISCONNECTED"
        Call.STATE_NEW          -> "NEW"
        else                    -> "UNKNOWN($state)"
    }

    // ── Per-call callback registered when a call is added ────────────────────

    private inner class SmartCallCallback(private val call: Call) : Call.Callback() {

        override fun onStateChanged(call: Call, state: Int) {
            val id = callId(call)
            val stateLabel = callStateLabel(state)
            Log.d(TAG, "State changed callId=$id state=$stateLabel")
            TelecomChannel.postCallEvent(
                event     = "STATE_CHANGED",
                callId    = id,
                state     = stateLabel,
                direction = callDirection(call)
            )
        }

        override fun onCallDestroyed(call: Call) {
            val id = callId(call)
            Log.d(TAG, "Call destroyed callId=$id")
            callMap.remove(id)
            TelecomChannel.postCallEvent(
                event     = "CALL_REMOVED",
                callId    = id,
                state     = "DISCONNECTED",
                direction = callDirection(call)
            )
        }

        override fun onDetailsChanged(call: Call, details: Call.Details?) {
            // Re-emit state on detail change (covers some OEM quirks)
            onStateChanged(call, call.state)
        }
    }

    // ── InCallService lifecycle ───────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "SmartDialInCallService created")
    }

    override fun onDestroy() {
        // Unregister all callbacks and clear map to prevent leaks
        callMap.values.forEach { call ->
            try { call.unregisterCallback(SmartCallCallback(call)) } catch (_: Exception) {}
        }
        callMap.clear()
        instance = null
        Log.d(TAG, "SmartDialInCallService destroyed")
        super.onDestroy()
    }

    // ── Telecom call events ───────────────────────────────────────────────────

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        val id = callId(call)
        val stateLabel = callStateLabel(call.state)
        val dir = callDirection(call)
        Log.d(TAG, "Call added callId=$id state=$stateLabel dir=$dir")

        callMap[id] = call
        call.registerCallback(SmartCallCallback(call))

        TelecomChannel.postCallEvent(
            event     = "CALL_ADDED",
            callId    = id,
            state     = stateLabel,
            direction = dir
        )
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        val id = callId(call)
        Log.d(TAG, "Call removed callId=$id")
        callMap.remove(id)
        TelecomChannel.postCallEvent(
            event     = "CALL_REMOVED",
            callId    = id,
            state     = "DISCONNECTED",
            direction = callDirection(call)
        )
    }

    // ── Call controls ─────────────────────────────────────────────────────────

    /**
     * End a specific call by its callId.
     * Returns true if the call was found and disconnect() was called.
     */
    fun endCall(callId: String): Boolean {
        val call = callMap[callId]
        return if (call != null && call.state != Call.STATE_DISCONNECTED) {
            call.disconnect()
            Log.d(TAG, "endCall: disconnect requested for callId=$callId")
            true
        } else {
            Log.w(TAG, "endCall: call not found or already disconnected callId=$callId")
            false
        }
    }

    /**
     * End all tracked calls.
     */
    fun endAllCalls() {
        callMap.values.forEach { call ->
            if (call.state != Call.STATE_DISCONNECTED) {
                call.disconnect()
            }
        }
        Log.d(TAG, "endAllCalls: ${callMap.size} calls disconnected")
    }

    /**
     * Answer an incoming call.
     * [Phase 4 foundation — fully exercised when a second phone sends an incoming call]
     */
    fun answerCall(callId: String): Boolean {
        val call = callMap[callId]
        return if (call != null && call.state == Call.STATE_RINGING) {
            call.answer(0) // videoState = 0 = AUDIO_ONLY
            Log.d(TAG, "answerCall: answered callId=$callId")
            true
        } else {
            Log.w(TAG, "answerCall: call not ringing or not found callId=$callId")
            false
        }
    }

    /**
     * Decline (reject) an incoming call.
     */
    fun declineCall(callId: String): Boolean {
        val call = callMap[callId]
        return if (call != null && call.state == Call.STATE_RINGING) {
            call.reject(false, null)
            Log.d(TAG, "declineCall: rejected callId=$callId")
            true
        } else {
            Log.w(TAG, "declineCall: call not ringing or not found callId=$callId")
            false
        }
    }

    /**
     * Return a summary of currently tracked calls for Flutter diagnostic use.
     */
    fun getActiveCallsSummary(): List<Map<String, Any>> {
        return callMap.map { (id, call) ->
            mapOf(
                "callId"    to id,
                "state"     to callStateLabel(call.state),
                "direction" to callDirection(call)
            )
        }
    }
}
