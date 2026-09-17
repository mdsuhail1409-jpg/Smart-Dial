# SmartDial Architecture

## ⚠️ IMPORTANT: Voice Call Path

SmartDial is an **intelligent Android cellular dialer**, NOT a VoIP application.

```
ACTUAL VOICE AUDIO PATH:
  Phone A
    │
    ▼
  Android Telecom Framework (TelecomManager)
    │
    ▼
  Selected SIM / PhoneAccount
    │
    ▼
  Mobile Carrier Network (Jio / Airtel / etc.)
    │
    ▼
  Phone B — RINGS AND RECEIVES CELLULAR CALL

WebRTC is NOT used for voice communication.
STUN / TURN are NOT used.
Voice does NOT travel through FastAPI or any cloud server.
```

## Cloud Path (Intent Coordination Only)

```
SmartDial App
    │
    │  HTTP/JSON (REST)
    ▼
FastAPI Backend  ──►  PostgreSQL
    │
    ▼
Communication Registry
  - Stores call intent: A → B
  - Stores call intent: B → A
  - (Phase 5) Detects reciprocal pair within ΔT window
  - (Phase 7) Resolves which call proceeds
    │
    ▼
Coordination Decision
    │
    ▼
Android Telecom (instructs SIM to place the call)
```

## Development Phases

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Authentication, JWT, user DB | ✅ DONE |
| 2 | Communication requests / call intents | ✅ DONE |
| 3 | Android Telecom + SIM calling | 🔄 CURRENT |
| 4 | Default dialer + InCallService stabilisation | ⬜ |
| 5 | Reciprocal detection: A→B + B→A | ⬜ |
| 6 | Real-time cloud sync (WebSocket for data only) | ⬜ |
| 7 | Conflict resolution | ⬜ |
| 8 | One approved SIM call proceeds | ⬜ |
| 9 | DND / VIP / context rules | ⬜ |
| 10 | History / notifications / monitoring | ⬜ |
| 11 | Two-phone reciprocal E2E test | ⬜ |
| 12 | Final stabilisation / APK / demo | ⬜ |

## Backend Layers

```
app/
├── main.py                         ← FastAPI app, routers, CORS
├── config.py                       ← Pydantic settings (.env)
│     REQUEST_TTL_SECONDS = 30
├── database.py                     ← SQLAlchemy engine + session
├── dependencies.py                 ← get_current_user (JWT)
├── models/
│   ├── user.py                     ← users table
│   └── communication_request.py   ← communication_requests table
├── schemas/
│   ├── auth.py
│   ├── user.py
│   └── call.py
├── routers/
│   ├── auth.py    POST /api/auth/register, /login
│   ├── users.py   GET  /api/users, /api/users/{id}
│   └── calls.py   POST /api/calls/request
│                  GET  /api/calls
│                  GET  /api/calls/{request_id}
│                  POST /api/calls/{request_id}/cancel
├── services/
│   └── call_request_service.py    ← business logic, TTL, expiry
├── security/
│   ├── jwt.py
│   └── password.py
└── utils/
    └── ids.py                      ← generate_request_id() → CR_XXXXXX
```

## Flutter / Android Layers

```
lib/
├── main.dart                              ← App entry + routing
├── core/
│   ├── api/api_client.dart                ← HTTP client
│   ├── constants/app_constants.dart       ← baseUrl (--dart-define)
│   ├── models/
│   │   ├── user.dart
│   │   └── call_request.dart
│   └── storage/secure_storage.dart        ← JWT keystore
├── services/
│   ├── auth_service.dart
│   ├── user_service.dart
│   ├── call_service.dart                  ← cloud call-intent API
│   └── telecom_service.dart               ← Android Telecom bridge
│         placeCellularCall(phone)         ← SIM call via TelecomManager
│         isDefaultDialer()
│         requestDefaultDialerRole()
│         callStateStream                  ← InCallService events
└── screens/
    ├── splash/
    ├── login/
    ├── register/
    ├── home/                              ← user list + CALL button
    ├── calling/                           ← intent + SIM call + state
    └── dialer_status/                     ← default dialer + SIM accounts

android/app/src/main/kotlin/com/smartdial/smartdial/
├── MainActivity.kt                        ← registers TelecomChannel
├── TelecomChannel.kt                      ← MethodChannel + EventChannel
└── SmartDialInCallService.kt              ← InCallService foundation
```

## Database Schema

```sql
-- Day 1
CREATE TABLE users (
  id            SERIAL PRIMARY KEY,
  name          VARCHAR(100)  NOT NULL,
  email         VARCHAR(255)  UNIQUE NOT NULL,
  phone         VARCHAR(20)   UNIQUE NOT NULL,  -- used for SIM calls
  password_hash VARCHAR(255)  NOT NULL,
  status        userstatus    NOT NULL DEFAULT 'ACTIVE',
  created_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- Day 2
CREATE TABLE communication_requests (
  id              SERIAL PRIMARY KEY,
  request_id      VARCHAR(20)   UNIQUE NOT NULL,  -- CR_XXXXXX
  caller_id       INTEGER       NOT NULL REFERENCES users(id),
  receiver_id     INTEGER       NOT NULL REFERENCES users(id),
  request_time    TIMESTAMPTZ   NOT NULL,
  status          requeststatus NOT NULL DEFAULT 'PENDING',
  reciprocal_flag BOOLEAN       NOT NULL DEFAULT FALSE,
  pair_id         VARCHAR(50),                    -- NULL until Phase 5
  expires_at      TIMESTAMPTZ   NOT NULL,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);
```

## Security Notes

- `caller_id` is NEVER accepted from Flutter — always from the verified JWT
- `password_hash` is NEVER returned by any API endpoint
- Phone numbers are used ONLY for SIM dialling — never for JWT identity
- Cloud identity uses `user.id`; cellular destination uses `user.phone`
- WebRTC is NOT present in this codebase
