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

from contextlib import asynccontextmanager

from app.database import Base, engine, SessionLocal
from app.routers import auth, users, calls, reciprocal, decision, websocket
from app.mongodb import get_mongo_client, sync_from_mongo_to_db

Base.metadata.create_all(bind=engine)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: sync users from MongoDB Atlas into local session if needed
    try:
        db = SessionLocal()
        sync_from_mongo_to_db(db)
        db.close()
    except Exception as exc:
        print(f"MongoDB startup sync notice: {exc}")
    yield


app = FastAPI(
    title="SmartDial API",
    description="Smart Reciprocal Call Coordination System",
    version="0.5.1",
    lifespan=lifespan,
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
app.include_router(websocket.router)


# ── Health check ─────────────────────────────────────────────────────────────
@app.get("/health", tags=["health"], summary="Health check")
def health_check() -> dict:
    mongo_ok = get_mongo_client() is not None
    return {
        "status": "ok",
        "service": "SmartDial API",
        "version": "0.5.1",
        "database": "mongodb_atlas" if mongo_ok else "sqlite",
        "mongodb_connected": mongo_ok,
    }

