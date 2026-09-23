"""
Decision Service — Phase 6

High-level orchestration for creating and retrieving communication decisions.

This service:
  1. Loads the reciprocal pair and verifies authorization.
  2. Returns the existing decision if one already exists (idempotency).
  3. Otherwise: builds context → runs conflict resolution → persists decision.
  4. Handles user responses (ALLOW_A_TO_B / ALLOW_B_TO_A / BLOCK).

CRITICAL: This service does NOT call TelecomManager or any Android API.
It only manages the logical decision layer.

Phase 7/8 will translate the decision into an actual Telecom action.
"""

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from app.models.reciprocal_pair import ReciprocalPair
from app.models.communication_decision import (
    CommunicationDecision,
    DecisionType,
    DecisionStatus,
    ReasonCode,
)
from app.models.user import User
from app.services.context_engine import build_context
from app.services.conflict_resolution_engine import resolve
from app.services.reciprocal_detection_service import get_pair_by_pid
from app.utils.ids import generate_decision_id

_MAX_DECISION_ID_RETRIES = 5


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _broadcast_decision_resolved(decision: CommunicationDecision, pair: ReciprocalPair) -> None:
    """Best-effort broadcast of DECISION_RESOLVED event with per-user action instructions."""
    try:
        from app.services.connection_manager import manager

        user_a_id = pair.request_a.caller_id
        user_b_id = pair.request_b.caller_id

        def get_user_action(user_id: int) -> str:
            d_type = decision.decision_type.value if hasattr(decision.decision_type, "value") else str(decision.decision_type)
            if d_type == "ALLOW_A_TO_B":
                return "PROCEED" if user_id == user_a_id else "STANDBY"
            elif d_type == "ALLOW_B_TO_A":
                return "PROCEED" if user_id == user_b_id else "STANDBY"
            elif d_type == "BLOCK":
                return "BLOCK"
            else:
                return "ASK_USER"

        base_event = {
            "event": "DECISION_RESOLVED",
            "pair_id": decision.pair_id,
            "decision_id": decision.decision_id,
            "decision_type": decision.decision_type.value if hasattr(decision.decision_type, "value") else str(decision.decision_type),
            "selected_request_id": decision.selected_request_id,
            "reason_code": decision.reason_code.value if hasattr(decision.reason_code, "value") else str(decision.reason_code),
            "status": decision.status.value if hasattr(decision.status, "value") else str(decision.status),
        }

        manager.publish_to_user_threadsafe(
            user_a_id,
            {**base_event, "action": get_user_action(user_a_id)},
        )
        manager.publish_to_user_threadsafe(
            user_b_id,
            {**base_event, "action": get_user_action(user_b_id)},
        )
    except Exception:
        pass


def _is_participant(pair: ReciprocalPair, user_id: int) -> bool:
    participants = {
        pair.request_a.caller_id,
        pair.request_a.receiver_id,
        pair.request_b.caller_id,
        pair.request_b.receiver_id,
    }
    return user_id in participants


# ── Create / evaluate decision ────────────────────────────────────────────────

def evaluate_decision(
    pair_id: str,
    current_user: User,
    db: Session,
) -> CommunicationDecision:
    """
    Evaluate or return the existing decision for a reciprocal pair.

    Idempotent: if a RESOLVED decision already exists for this pair, it is
    returned without creating a new one.

    Authorization: only participants of the pair may trigger evaluation.

    Raises:
        LookupError   — pair not found
        PermissionError — current user is not a participant
    """
    # Load and authorize
    pair = get_pair_by_pid(
        pair_id         = pair_id,
        current_user_id = current_user.id,
        db              = db,
    )

    # Idempotency: return existing decision
    existing = db.query(CommunicationDecision).filter(
        CommunicationDecision.pair_id == pair_id
    ).first()
    if existing is not None:
        return existing

    # Build context
    context = build_context(pair, db)

    # Run conflict resolution
    result = resolve(
        context   = context,
        request_a = pair.request_a,
        request_b = pair.request_b,
    )

    # Generate unique decision_id
    decision_id_str: Optional[str] = None
    for _ in range(_MAX_DECISION_ID_RETRIES):
        candidate = generate_decision_id()
        if db.query(CommunicationDecision).filter(
            CommunicationDecision.decision_id == candidate
        ).first() is None:
            decision_id_str = candidate
            break
    if decision_id_str is None:
        raise RuntimeError("Failed to generate a unique decision ID")

    decision = CommunicationDecision(
        decision_id          = decision_id_str,
        pair_id              = pair_id,
        decision_type        = result.decision_type,
        selected_request_id  = result.selected_request.id if result.selected_request else None,
        reason_code          = result.reason_code,
        context_snapshot     = context.to_json(),
        status               = DecisionStatus.RESOLVED,
    )
    db.add(decision)

    try:
        db.commit()
        db.refresh(decision)
        _broadcast_decision_resolved(decision, pair)
        return decision
    except IntegrityError:
        # Race: another thread created the decision between our check and insert
        db.rollback()
        existing = db.query(CommunicationDecision).filter(
            CommunicationDecision.pair_id == pair_id
        ).first()
        if existing:
            return existing
        raise


# ── Read decision ─────────────────────────────────────────────────────────────

def get_decision(
    pair_id: str,
    current_user: User,
    db: Session,
) -> CommunicationDecision:
    """
    Return the decision for a pair.

    Raises:
        LookupError   — pair or decision not found
        PermissionError — not a participant
    """
    pair = get_pair_by_pid(
        pair_id         = pair_id,
        current_user_id = current_user.id,
        db              = db,
    )
    decision = db.query(CommunicationDecision).filter(
        CommunicationDecision.pair_id == pair_id
    ).first()
    if decision is None:
        raise LookupError(f"No decision found for pair {pair_id!r}")
    return decision


# ── User response (ASK_USER → explicit choice) ────────────────────────────────

_VALID_RESPONSE_ACTIONS = {
    DecisionType.ALLOW_A_TO_B.value,
    DecisionType.ALLOW_B_TO_A.value,
    DecisionType.BLOCK.value,
}


def respond_to_decision(
    pair_id: str,
    action: str,
    current_user: User,
    db: Session,
) -> CommunicationDecision:
    """
    Record an explicit user choice for an ASK_USER decision.

    Rules:
    - Only participants may respond.
    - action must be ALLOW_A_TO_B | ALLOW_B_TO_A | BLOCK.
    - If the decision is already RESOLVED with an explicit choice,
      responding again replaces it (last writer wins).
    - The function does NOT place or cancel any SIM call.

    Raises:
        LookupError   — pair or decision not found
        PermissionError — not a participant
        ValueError    — invalid action
    """
    if action not in _VALID_RESPONSE_ACTIONS:
        raise ValueError(
            f"Invalid action {action!r}. "
            f"Must be one of {sorted(_VALID_RESPONSE_ACTIONS)}"
        )

    pair = get_pair_by_pid(
        pair_id         = pair_id,
        current_user_id = current_user.id,
        db              = db,
    )

    decision = db.query(CommunicationDecision).filter(
        CommunicationDecision.pair_id == pair_id
    ).first()
    if decision is None:
        raise LookupError(f"No decision found for pair {pair_id!r}")

    new_type = DecisionType(action)

    # Resolve selected_request_id for ALLOW decisions
    selected_id: Optional[int] = None
    if new_type == DecisionType.ALLOW_A_TO_B:
        selected_id = pair.request_a_id
    elif new_type == DecisionType.ALLOW_B_TO_A:
        selected_id = pair.request_b_id

    decision.decision_type       = new_type
    decision.selected_request_id = selected_id
    decision.reason_code         = ReasonCode.EXPLICIT_USER_CHOICE
    decision.status              = DecisionStatus.RESOLVED

    db.commit()
    db.refresh(decision)
    _broadcast_decision_resolved(decision, pair)
    return decision
