# SmartDial — Physical Two-Phone Testing Guide (Phase 11)

This guide details how to verify SmartDial's real cellular collision resolution using two physical Android phones equipped with active carrier SIM cards.

---

## 1. Prerequisites

1. **Two Android Phones**:
   - Phone A (e.g., Xiaomi Redmi Note 13 Pro) with active carrier SIM card (Number A).
   - Phone B with active carrier SIM card (Number B).
   - Both running Android 8.0+ (API 26+) with Android Telecom framework support.
2. **Local Network / Backend**:
   - FastAPI backend running on host PC: `http://<HOST_IP>:8000`.
   - Both phones connected to the same Wi-Fi network as host PC (or connected via ADB reverse proxy).
3. **App Installed**:
   - SmartDial installed on both Phone A and Phone B.
   - Set as **Default Dialer** on both phones (`Settings > Apps > Default Apps > Phone app > SmartDial`).

---

## 2. Test Setup & User Configuration

1. **Launch SmartDial on Phone A**:
   - Register user: `Alice` (Phone: Number A).
   - In Preferences, set Reciprocal Call Preference to: `PREFER_OUTGOING`.
2. **Launch SmartDial on Phone B**:
   - Register user: `Bob` (Phone: Number B).
   - In Preferences, set Reciprocal Call Preference to: `ASK` (or default).
3. Both phones will automatically connect to the real-time WebSocket `/ws/calls`.

---

## 3. Test Execution — Simultaneous Cellular Call Collision

1. **Simultaneous Dialing**:
   - On Phone A: Open SmartDial keypad or contact list, select `Bob`, and tap **Call**.
   - On Phone B: Within 5 seconds, open SmartDial, select `Alice`, and tap **Call**.
2. **Backend Detection & Real-Time Sync**:
   - Intent A and Intent B are registered in the cloud intent registry.
   - Server reciprocal detection engine locks both intents within milliseconds and pairs them (`RP_XXXXXX`).
   - Push event `RECIPROCAL_DETECTED` is delivered simultaneously to both phones via WebSocket.
3. **Coordinated Resolution**:
   - Decision engine evaluates Alice's `PREFER_OUTGOING` preference.
   - Alice's screen receives `PROCEED` → Phone A initiates outgoing carrier cellular SIM call via `TelecomManager.placeCall()`.
   - Bob's screen receives `STANDBY` → Phone B immediately aborts its outgoing attempt and displays:
     > *"Incoming carrier call from Alice — Standing by to receive..."*
4. **Physical Carrier Network Connection**:
   - Phone B's screen rings with an incoming carrier phone call from Alice.
   - Bob answers the call.
   - Real cellular audio connects with **zero collision** and **no busy tone**.
5. **Telemetry & Audit**:
   - Open **Collision History & Telemetry** on either phone (`bolt icon` in the home app bar) to see the exact time difference (e.g. `Δ 128 ms`) and the resolution rule logged.
