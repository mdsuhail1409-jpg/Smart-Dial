package com.smartdial.smartdial

import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.telecom.Call
import android.telecom.PhoneAccount
import android.telecom.TelecomManager
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * TelecomChannel — Phase 4
 *
 * Single entry-point for all Flutter ↔ Android Telecom communication.
 *
 * MethodChannel  "com.smartdial/telecom":
 *   isTelecomSupported()             → Boolean
 *   isDefaultDialer()                → Boolean
 *   requestDefaultDialerRole()       → String ("requested" | "already_default")
 *   placeCellularCall(number)        → Boolean
 *   getAvailablePhoneAccounts()      → List<Map>
 *   endCall(callId)                  → Boolean
 *   answerCall(callId)               → Boolean  [Phase 4 foundation]
 *   declineCall(callId)              → Boolean  [Phase 4 foundation]
 *   getActiveCalls()                 → List<Map>
 *
 * EventChannel   "com.smartdial/call_events":
 *   Stream<Map> — structured call events:
 *     { "event": "CALL_ADDED"|"STATE_CHANGED"|"CALL_REMOVED",
 *       "callId": "...",
 *       "state": "DIALING"|"RINGING"|"ACTIVE"|"HOLDING"|"DISCONNECTED"|...,
 *       "direction": "OUTGOING"|"INCOMING"|"UNKNOWN" }
 *
 * IMPORTANT: No WebRTC, no SDP, no ICE. Audio travels via SIM/carrier.
 */
object TelecomChannel : MethodChannel.MethodCallHandler {

    private const val TAG = "TelecomChannel"
    const val METHOD_CHANNEL = "com.smartdial/telecom"
    const val EVENT_CHANNEL  = "com.smartdial/call_events"

    private var context: Context? = null
    private var activity: MainActivity? = null
    private var eventSink: EventChannel.EventSink? = null

    // ── Setup ─────────────────────────────────────────────────────────────────

    fun register(engine: FlutterEngine, mainActivity: MainActivity) {
        activity = mainActivity
        context  = mainActivity.applicationContext

        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler(this)

        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    Log.d(TAG, "Call events EventChannel listening")
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    Log.d(TAG, "Call events EventChannel cancelled")
                }
            })
    }

    /**
     * Post a structured call event to Flutter.
     * Called from SmartDialInCallService whenever a call state changes.
     *
     * @param event  One of: CALL_ADDED, STATE_CHANGED, CALL_REMOVED
     * @param callId A stable identifier for this call (system-assigned)
     * @param state  Human-readable state: DIALING, RINGING, ACTIVE, HOLDING, DISCONNECTED …
     * @param direction OUTGOING | INCOMING | UNKNOWN
     */
    fun postCallEvent(
        event: String,
        callId: String,
        state: String,
        direction: String = "UNKNOWN"
    ) {
        activity?.runOnUiThread {
            val payload = mapOf(
                "event"     to event,
                "callId"    to callId,
                "state"     to state,
                "direction" to direction,
            )
            eventSink?.success(payload)
            Log.d(TAG, "Event posted: $event callId=$callId state=$state dir=$direction")
        }
    }

    // ── MethodCallHandler ─────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isTelecomSupported"        -> handleIsTelecomSupported(result)
            "isDefaultDialer"           -> handleIsDefaultDialer(result)
            "requestDefaultDialerRole"  -> handleRequestDefaultDialerRole(result)
            "placeCellularCall"         -> handlePlaceCellularCall(call, result)
            "getAvailablePhoneAccounts" -> handleGetPhoneAccounts(result)
            "endCall"                   -> handleEndCall(call, result)
            "answerCall"                -> handleAnswerCall(call, result)
            "declineCall"               -> handleDeclineCall(call, result)
            "getActiveCalls"            -> handleGetActiveCalls(result)
            else                        -> result.notImplemented()
        }
    }

    // ── Telecom query handlers ────────────────────────────────────────────────

    private fun handleIsTelecomSupported(result: MethodChannel.Result) {
        val tm = context?.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
        result.success(tm != null)
    }

    private fun handleIsDefaultDialer(result: MethodChannel.Result) {
        val ctx = context ?: return result.success(false)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = ctx.getSystemService(Context.ROLE_SERVICE) as RoleManager
            result.success(rm.isRoleHeld(RoleManager.ROLE_DIALER))
        } else {
            val tm = ctx.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
            result.success(tm?.defaultDialerPackage == ctx.packageName)
        }
    }

    private fun handleRequestDefaultDialerRole(result: MethodChannel.Result) {
        val ctx = context ?: return result.error("NO_CONTEXT", "Context unavailable", null)
        val act = activity ?: return result.error("NO_ACTIVITY", "Activity unavailable", null)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val rm = ctx.getSystemService(Context.ROLE_SERVICE) as RoleManager
                if (!rm.isRoleAvailable(RoleManager.ROLE_DIALER)) {
                    return result.error("ROLE_UNAVAILABLE", "ROLE_DIALER not available on this device", null)
                }
                if (rm.isRoleHeld(RoleManager.ROLE_DIALER)) {
                    return result.success("already_default")
                }
                val intent = rm.createRequestRoleIntent(RoleManager.ROLE_DIALER)
                act.startActivityForResult(intent, MainActivity.REQUEST_DEFAULT_DIALER)
                result.success("requested")
            } else {
                val intent = Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER)
                    .putExtra(TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME, ctx.packageName)
                act.startActivity(intent)
                result.success("requested")
            }
        } catch (e: Exception) {
            Log.e(TAG, "requestDefaultDialerRole failed", e)
            result.error("REQUEST_FAILED", e.message, null)
        }
    }

    private fun handlePlaceCellularCall(call: MethodCall, result: MethodChannel.Result) {
        val number = call.argument<String>("number")
        if (number.isNullOrBlank()) {
            return result.error("INVALID_NUMBER", "Phone number must not be empty", null)
        }
        val cleaned = number.trim()
        if (cleaned.length < 5) {
            return result.error("INVALID_NUMBER", "Phone number '$cleaned' is too short", null)
        }

        val ctx = context ?: return result.error("NO_CONTEXT", "Context unavailable", null)
        val act = activity ?: return result.error("NO_ACTIVITY", "Activity unavailable", null)

        try {
            val uri = Uri.fromParts("tel", cleaned, null)
            Log.d(TAG, "Attempting cellular call to $cleaned")

            // Strategy 1: TelecomManager.placeCall (requires default dialer or CALL_PHONE)
            val tm = ctx.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            try {
                tm.placeCall(uri, null)
                Log.d(TAG, "TelecomManager.placeCall succeeded")
                result.success(true)
                return
            } catch (se: SecurityException) {
                Log.w(TAG, "TelecomManager.placeCall denied, trying ACTION_CALL: ${se.message}")
            }

            // Strategy 2: ACTION_CALL — works with CALL_PHONE permission
            val callIntent = Intent(Intent.ACTION_CALL, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (callIntent.resolveActivity(ctx.packageManager) != null) {
                act.startActivity(callIntent)
                Log.d(TAG, "ACTION_CALL dispatched")
                result.success(true)
                return
            }

            // Strategy 3: ACTION_DIAL — last resort, user taps call button
            val dialIntent = Intent(Intent.ACTION_DIAL, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            act.startActivity(dialIntent)
            Log.d(TAG, "ACTION_DIAL fallback dispatched")
            result.success(true)

        } catch (e: Exception) {
            Log.e(TAG, "All call strategies failed", e)
            result.error("CALL_FAILED", e.message, null)
        }
    }

    private fun handleGetPhoneAccounts(result: MethodChannel.Result) {
        val ctx = context ?: return result.success(emptyList<Map<String, Any>>())
        try {
            val tm = ctx.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            val accounts = tm.callCapablePhoneAccounts
            val list = accounts.mapIndexed { index, handle ->
                val account: PhoneAccount? = tm.getPhoneAccount(handle)
                mapOf(
                    "id"       to handle.id,
                    "label"    to (account?.label?.toString() ?: "SIM ${index + 1}"),
                    "enabled"  to (account?.isEnabled ?: true),
                    "index"    to index
                )
            }
            result.success(list)
        } catch (se: SecurityException) {
            Log.w(TAG, "READ_PHONE_STATE needed for PhoneAccounts", se)
            result.success(emptyList<Map<String, Any>>())
        } catch (e: Exception) {
            Log.e(TAG, "getPhoneAccounts failed", e)
            result.success(emptyList<Map<String, Any>>())
        }
    }

    // ── Call control handlers ─────────────────────────────────────────────────

    private fun handleEndCall(call: MethodCall, result: MethodChannel.Result) {
        val callId = call.argument<String>("callId")
        val service = SmartDialInCallService.instance
        if (service == null) {
            Log.w(TAG, "endCall: InCallService not bound — SmartDial may not be default dialer")
            result.error("SERVICE_NOT_BOUND",
                "InCallService not bound. SmartDial must be the default phone app to end calls.", null)
            return
        }
        val ended = if (callId != null) service.endCall(callId) else service.endAllCalls().let { true }
        Log.d(TAG, "endCall callId=$callId result=$ended")
        result.success(ended)
    }

    private fun handleAnswerCall(call: MethodCall, result: MethodChannel.Result) {
        val callId = call.argument<String>("callId")
        val service = SmartDialInCallService.instance
        if (service == null) {
            result.error("SERVICE_NOT_BOUND", "InCallService not bound", null)
            return
        }
        val answered = if (callId != null) service.answerCall(callId) else false
        Log.d(TAG, "answerCall callId=$callId result=$answered")
        result.success(answered)
    }

    private fun handleDeclineCall(call: MethodCall, result: MethodChannel.Result) {
        val callId = call.argument<String>("callId")
        val service = SmartDialInCallService.instance
        if (service == null) {
            result.error("SERVICE_NOT_BOUND", "InCallService not bound", null)
            return
        }
        val declined = if (callId != null) service.declineCall(callId) else false
        Log.d(TAG, "declineCall callId=$callId result=$declined")
        result.success(declined)
    }

    private fun handleGetActiveCalls(result: MethodChannel.Result) {
        val service = SmartDialInCallService.instance
        if (service == null) {
            result.success(emptyList<Map<String, Any>>())
            return
        }
        result.success(service.getActiveCallsSummary())
    }
}
