"""
SmartDial FastAPI application entry point.

Routes:
  GET  /health                              → health check (no auth)
  POST /api/auth/register                   → create account
  POST /api/auth/login                      → authenticate + receive JWT
  GET  /api/users                           → list users            (auth required)
  GET  /api/users/{id}                      → single user           (auth required)
  POST /api/calls/request                   → create call intent    (auth required)
  GET  /api/calls                           → my call requests      (auth required)
  GET  /api/calls/{request_id}              → single request        (auth required)
  POST /api/calls/{request_id}/cancel       → cancel request        (auth required)
  GET  /api/reciprocal-pairs                → my reciprocal pairs   (auth required)
  GET  /api/reciprocal-pairs/{pair_id}      → single pair           (auth required)
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import auth, users, calls, reciprocal, decision

app = FastAPI(
    title="SmartDial API",
    description="Smart Reciprocal Call Coordination System",
    version="0.4.0",
)

# CORS — open for development; tighten for production
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Routers ──────────────────────────────────────────────────────────────────
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(calls.router)
app.include_router(reciprocal.router)
app.include_router(decision.router)


# ── Health check ─────────────────────────────────────────────────────────────
@app.get("/health", tags=["health"], summary="Health check")
def health_check() -> dict:
    return {"status": "ok", "service": "SmartDial API"}
