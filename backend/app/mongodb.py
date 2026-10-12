"""
MongoDB Atlas persistent storage layer for SmartDial.

Guarantees data permanence across Render container cold starts,
ephemeral container wipes, and server restarts.
"""

import logging
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List
from pymongo import MongoClient
from pymongo.collection import Collection

from app.config import get_settings

logger = logging.getLogger("smartdial.mongodb")

_client: Optional[MongoClient] = None


def get_mongo_client() -> Optional[MongoClient]:
    """Return a singleton MongoClient instance or None if connection fails."""
    global _client
    if _client is not None:
        return _client

    settings = get_settings()
    mongo_url = getattr(settings, "MONGODB_URL", None)
    if not mongo_url:
        # Default to configured Atlas cluster if not explicitly set in env
        mongo_url = (
            "mongodb+srv://suhailzia14_db_user:hnxlZb7w4Ov86nNA"
            "@smart-dial.n7jazjh.mongodb.net/smartdial?retryWrites=true&w=majority&appName=Smart-Dial"
        )

    try:
        _client = MongoClient(mongo_url, serverSelectionTimeoutMS=5000)
        # Ping the server to verify connection
        _client.admin.command("ping")
        logger.info("Successfully connected to MongoDB Atlas (database: smartdial)")
        return _client
    except Exception as exc:
        logger.warning(f"Could not connect to MongoDB Atlas: {exc}")
        return None


def get_collection(name: str) -> Optional[Collection]:
    """Get a specific collection from the smartdial database."""
    client = get_mongo_client()
    if client is None:
        return None
    try:
        db = client["smartdial"]
        return db[name]
    except Exception as exc:
        logger.warning(f"Failed to access collection {name}: {exc}")
        return None


# ── User Operations ───────────────────────────────────────────────────────────

def save_user(user_data: Dict[str, Any]) -> bool:
    """Save or update a user document in MongoDB Atlas."""
    coll = get_collection("users")
    if coll is None:
        return False
    try:
        user_id = user_data.get("id")
        email = user_data.get("email")
        query = {"email": email} if email else {"id": user_id}
        # Avoid storing Mongo's _id when replacing
        doc = {k: v for k, v in user_data.items() if k != "_id"}
        doc["updated_at_mongo"] = datetime.now(timezone.utc).isoformat()
        coll.replace_one(query, doc, upsert=True)
        return True
    except Exception as exc:
        logger.error(f"Failed to save user {user_data.get('email')} to MongoDB Atlas: {exc}")
        return False


def sync_user_to_mongo(user) -> bool:
    """Convenience helper to serialize an ORM User into MongoDB Atlas."""
    data = {
        "id": user.id,
        "name": user.name,
        "email": user.email,
        "phone": user.phone,
        "password_hash": user.password_hash,
        "status": user.status.value if hasattr(user.status, "value") else str(user.status),
        "reciprocal_call_preference": user.reciprocal_call_preference.value if hasattr(user.reciprocal_call_preference, "value") else str(user.reciprocal_call_preference),
        "dnd_enabled": getattr(user, "dnd_enabled", False),
        "vip_contacts": getattr(user, "vip_contacts", ""),
    }
    return save_user(data)


def sync_from_mongo_to_db(db_session) -> int:
    """Restore users from MongoDB Atlas into local DB if not already present."""
    from app.models.user import User, UserStatus, ReciprocalCallPreference
    users = get_all_users()
    restored = 0
    for u in users:
        existing = db_session.query(User).filter(User.email == u.get("email")).first()
        if not existing:
            pref = u.get("reciprocal_call_preference", "ASK")
            try:
                pref_enum = ReciprocalCallPreference(pref)
            except Exception:
                pref_enum = ReciprocalCallPreference.ASK

            new_u = User(
                id=u.get("id"),
                name=u.get("name"),
                email=u.get("email"),
                phone=u.get("phone"),
                password_hash=u.get("password_hash"),
                status=UserStatus.ACTIVE,
                reciprocal_call_preference=pref_enum,
                dnd_enabled=bool(u.get("dnd_enabled", False)),
                vip_contacts=str(u.get("vip_contacts", "") or ""),
            )
            db_session.add(new_u)
            restored += 1
    if restored > 0:
        try:
            db_session.commit()
            logger.info(f"Restored {restored} users from MongoDB Atlas")
        except Exception as exc:
            db_session.rollback()
            logger.warning(f"Error during MongoDB restore commit: {exc}")
    return restored


def get_user_by_email(email: str) -> Optional[Dict[str, Any]]:
    """Retrieve a user document by email from MongoDB Atlas."""
    coll = get_collection("users")
    if coll is None:
        return None
    try:
        return coll.find_one({"email": email})
    except Exception as exc:
        logger.error(f"Failed to find user {email} in MongoDB: {exc}")
        return None


def get_user_by_phone(phone: str) -> Optional[Dict[str, Any]]:
    """Retrieve a user document by phone from MongoDB Atlas."""
    coll = get_collection("users")
    if coll is None:
        return None
    try:
        return coll.find_one({"phone": phone})
    except Exception as exc:
        logger.error(f"Failed to find user by phone {phone} in MongoDB: {exc}")
        return None


def get_all_users() -> List[Dict[str, Any]]:
    """Retrieve all users stored in MongoDB Atlas."""
    coll = get_collection("users")
    if coll is None:
        return []
    try:
        return list(coll.find({}))
    except Exception as exc:
        logger.error(f"Failed to fetch users from MongoDB: {exc}")
        return []


# ── Communication Request Operations ──────────────────────────────────────────

def save_request(req_data: Dict[str, Any]) -> bool:
    """Save or update a communication request in MongoDB Atlas."""
    coll = get_collection("communication_requests")
    if coll is None:
        return False
    try:
        req_id = req_data.get("request_id")
        coll.replace_one({"request_id": req_id}, req_data, upsert=True)
        return True
    except Exception as exc:
        logger.error(f"Failed to save request {req_data.get('request_id')} to MongoDB: {exc}")
        return False


# ── Reciprocal Pair Operations ────────────────────────────────────────────────

def save_pair(pair_data: Dict[str, Any]) -> bool:
    """Save or update a reciprocal pair in MongoDB Atlas."""
    coll = get_collection("reciprocal_pairs")
    if coll is None:
        return False
    try:
        pid = pair_data.get("pair_id")
        coll.replace_one({"pair_id": pid}, pair_data, upsert=True)
        return True
    except Exception as exc:
        logger.error(f"Failed to save pair {pair_data.get('pair_id')} to MongoDB: {exc}")
        return False


# ── Communication Decision Operations ─────────────────────────────────────────

def save_decision(decision_data: Dict[str, Any]) -> bool:
    """Save or update a communication decision in MongoDB Atlas."""
    coll = get_collection("communication_decisions")
    if coll is None:
        return False
    try:
        did = decision_data.get("decision_id")
        coll.replace_one({"decision_id": did}, decision_data, upsert=True)
        return True
    except Exception as exc:
        logger.error(f"Failed to save decision {decision_data.get('decision_id')} to MongoDB: {exc}")
        return False
