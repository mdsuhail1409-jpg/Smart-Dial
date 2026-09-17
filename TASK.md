# SmartDial Development

---

## Phase 1 — Auth + PostgreSQL — COMPLETE ✅
## Phase 2 — Communication Intent Registry — COMPLETE ✅
## Phase 3 — Android Telecom + SIM code — COMPLETE ✅ (physical test deferred)
## Phase 4 — Default Dialer + InCallService — COMPLETE ✅

---

## Phase 5 — Reciprocal Call Detection — COMPLETE ✅

### New backend additions

- [x] `RECIPROCAL_WINDOW_SECONDS = 10` added to `app/config.py`
- [x] `generate_pair_id()` added to `app/utils/ids.py` — produces `RP_XXXXXX`
- [x] `app/models/reciprocal_pair.py` — `ReciprocalPair` model:
  - id, pair_id (unique, indexed), request_a_id (FK), request_b_id (FK)
  - detected_at, time_difference_ms, status (DETECTED + future stubs)
  - UniqueConstraint on request_a_id and request_b_id (one request → one pair max)
- [x] `app/models/__init__.py` updated — Alembic picks up new model
- [x] `app/schemas/reciprocal.py` — response schemas
- [x] `app/routers/reciprocal.py` — GET /api/reciprocal-pairs, GET /api/reciprocal-pairs/{pair_id}
- [x] `app/services/reciprocal_detection_service.py`:
  - `detect_reciprocal()` — full detection engine with row-locking
  - Eligibility: PENDING + not already paired
  - Direction check: caller=receiver AND receiver=caller (exact reverse)
  - Time window: |t_a - t_b| ≤ RECIPROCAL_WINDOW_SECONDS (boundary inclusive)
  - Atomic pair creation + update of both requests
  - Idempotency: IntegrityError on race → reuse existing pair
  - `get_pair_by_pid()` — with participant-only authorisation
  - `get_my_pairs()` — returns only authenticated user's pairs
- [x] Detection wired into `POST /api/calls/request` — runs after commit
- [x] `app/main.py` updated — reciprocal router registered, version 0.3.0

### Database migration
- [x] Alembic revision `a9f4896d337e` generated and inspected
- [x] `alembic upgrade head` applied — `reciprocal_pairs` table in PostgreSQL
- [x] Table verified: 9 columns, unique pair_id, FK constraints, UniqueConstraints

### Tests

#### Backend unit tests — 57 / 57 PASSED (was 40, +17 Phase 5)
| Test | Result |
|------|--------|
| No pair without reverse | ✅ |
| Pair within 3s window | ✅ |
| Exact boundary (10s) | ✅ |
| Outside window (11s) = no match | ✅ |
| Same direction A→B+A→B = no match | ✅ |
| Wrong receiver C→A = no match | ✅ |
| Wrong caller B→C = no match | ✅ |
| CANCELLED request = no match | ✅ |
| EXPIRED request = no match | ✅ |
| Same timestamp = match | ✅ |
| Idempotency = ONE pair | ✅ |
| Concurrent detection = ONE pair | ✅ |
| Third user cannot access pair → 403 | ✅ |
| Participant can access pair → 200 | ✅ |
| GET /api/reciprocal-pairs (my pairs) | ✅ |
| Same pair_id on both requests | ✅ |
| pair_id format starts with RP_ | ✅ |

#### Integration smoke test — ALL PASSED
- Phase 5 PostgreSQL verified: `RP_xxxxxx` pair created, both requests updated
- DB: `reciprocal_flag=True`, `pair_id=RP_xxx` on both communication_requests
- `time_difference_ms` correct (29ms in live test)
- Third-user auth rejection confirmed (403)

### Flutter
- [x] CallingScreen updated — shows "RECIPROCAL CALL DETECTED / Pair: RP_xxx" badge when matched

---

## Quality Gates — Phase 5

| Check | Result |
|-------|--------|
| Backend unit tests | **57 / 57** |
| Integration smoke tests | **All PASSED** |
| Flutter unit tests (state mapper) | **15 / 15** |
| flutter analyze | **No issues found** |
| Android debug APK | **PASS** |
| WebRTC in codebase | **ABSENT** |

---

## Deferred Tests (second phone required)
- Real outgoing SIM call DIALING → ACTIVE → DISCONNECTED
- Real incoming call RINGING → ANSWER
- Phase 3/4 cellular verification
- Two-phone reciprocal E2E (A calls B + B calls A → pair detected → one SIM call proceeds)

---

## Phase 6–12 — NOT STARTED

| Phase | Description |
|-------|-------------|
| 6 | Decision / conflict resolution (which SIM call proceeds) |
| 7 | WebSocket real-time data sync |
| 8 | One approved SIM call proceeds |
| 9 | DND / VIP / context rules |
| 10 | History / notifications / monitoring |
| 11 | Two-phone reciprocal E2E test |
| 12 | Final stabilisation / APK / demo |
