"""
Conflict Resolution Engine — Phase 6

Applies a deterministic, rule-based policy to produce a CommunicationDecision
given a ContextSnapshot and the reciprocal pair.

CRITICAL: This engine does NOT place, cancel, answer, or suppress any SIM/
cellular call.  It produces a logical decision only.  Phase 7/8 will execute
the decision through Android Telecom.

Decision priority (applied in strict order — same input always = same output):

  Priority 1 — BLOCK_RECIPROCAL preference (either user)
      If user A or user B has BLOCK_RECIPROCAL preference:
      → BLOCK / USER_PREFERENCE

  Priority 2 — ALWAYS_ALLOW preference (either user)
      If user A or user B has ALWAYS_ALLOW preference:
      → ALLOW_A_TO_B (first request chronologically) / USER_PREFERENCE

  Priority 3 — PREFER_OUTGOING (user A = caller of request_a)
      User A prefers their own outgoing call to proceed:
      → ALLOW_A_TO_B / USER_PREFERENCE

  Priority 4 — PREFER_OUTGOING (user B = caller of request_b)
      User B prefers their own outgoing call to proceed:
      → ALLOW_B_TO_A / USER_PREFERENCE

  Priority 5 — PREFER_INCOMING (user A)
      User A prefers the other party's call to proceed (i.e. B→A):
      → ALLOW_B_TO_A / USER_PREFERENCE

  Priority 6 — PREFER_INCOMING (user B)
      User B prefers the other party's call to proceed (i.e. A→B):
      → ALLOW_A_TO_B / USER_PREFERENCE

  Priority 7 — Default
      Neither user has a decisive preference:
      → ASK_USER / DEFAULT_POLICY

The engine is stateless and pure: given the same ContextSnapshot, it always
returns the same result.
"""

from dataclasses import dataclass
from typing import Optional

from app.models.communication_request import CommunicationRequest
from app.models.communication_decision import DecisionType, ReasonCode
from app.models.user import ReciprocalCallPreference
from app.services.context_engine import ContextSnapshot


@dataclass
class ResolutionResult:
    """Output of the conflict resolution engine."""
    decision_type:       DecisionType
    selected_request:    Optional[CommunicationRequest]   # None for ASK_USER/BLOCK
    reason_code:         ReasonCode


def resolve(
    context:   ContextSnapshot,
    request_a: CommunicationRequest,   # earlier request (req_a in the pair)
    request_b: CommunicationRequest,   # later  request  (req_b in the pair)
) -> ResolutionResult:
    """
    Apply the documented priority rules and return a ResolutionResult.

    Parameters:
        context    — context snapshot built by context_engine.build_context()
        request_a  — the CommunicationRequest with the earlier request_time
        request_b  — the CommunicationRequest with the later  request_time
    """
    pref_a = context.user_a_preference
    pref_b = context.user_b_preference

    dnd_a = getattr(context, "dnd_a", "FALSE") == "TRUE"
    dnd_b = getattr(context, "dnd_b", "FALSE") == "TRUE"
    vip_a = getattr(context, "vip_a_in_b_contacts", "FALSE") == "TRUE"
    vip_b = getattr(context, "vip_b_in_a_contacts", "FALSE") == "TRUE"

    # ── Phase 9 Priority 0A: Mutual DND without VIP bypass ──────────────────
    if dnd_a and dnd_b and not vip_a and not vip_b:
        return ResolutionResult(
            decision_type    = DecisionType.BLOCK,
            selected_request = None,
            reason_code      = ReasonCode.DND_ACTIVE,
        )

    # ── Phase 9 Priority 0B: Individual DND + VIP Bypass ────────────────────
    if dnd_b:
        if vip_a:
            # VIP breaks through User B's DND
            return ResolutionResult(
                decision_type    = DecisionType.ALLOW_A_TO_B,
                selected_request = request_a,
                reason_code      = ReasonCode.VIP_PRIORITY,
            )
        else:
            # User B cannot receive calls, but if User A has DND off, B's call can reach A
            if not dnd_a:
                return ResolutionResult(
                    decision_type    = DecisionType.ALLOW_B_TO_A,
                    selected_request = request_b,
                    reason_code      = ReasonCode.DND_ACTIVE,
                )

    if dnd_a:
        if vip_b:
            # VIP breaks through User A's DND
            return ResolutionResult(
                decision_type    = DecisionType.ALLOW_B_TO_A,
                selected_request = request_b,
                reason_code      = ReasonCode.VIP_PRIORITY,
            )
        else:
            # User A cannot receive calls, but if User B has DND off, A's call can reach B
            if not dnd_b:
                return ResolutionResult(
                    decision_type    = DecisionType.ALLOW_A_TO_B,
                    selected_request = request_a,
                    reason_code      = ReasonCode.DND_ACTIVE,
                )

    # ── Phase 9 Priority 0C: VIP Contact Asymmetry (No active DND) ──────────
    if vip_a and not vip_b:
        return ResolutionResult(
            decision_type    = DecisionType.ALLOW_A_TO_B,
            selected_request = request_a,
            reason_code      = ReasonCode.VIP_PRIORITY,
        )
    elif vip_b and not vip_a:
        return ResolutionResult(
            decision_type    = DecisionType.ALLOW_B_TO_A,
            selected_request = request_b,
            reason_code      = ReasonCode.VIP_PRIORITY,
        )

    # ── Priority 1: Either user wants to block reciprocal calls ─────────────
    if (pref_a == ReciprocalCallPreference.BLOCK_RECIPROCAL.value or
            pref_b == ReciprocalCallPreference.BLOCK_RECIPROCAL.value):
        return ResolutionResult(
            decision_type    = DecisionType.BLOCK,
            selected_request = None,
            reason_code      = ReasonCode.USER_PREFERENCE,
        )

    # ── Priority 2: Either user always allows ────────────────────────────────
    if (pref_a == ReciprocalCallPreference.ALWAYS_ALLOW.value or
            pref_b == ReciprocalCallPreference.ALWAYS_ALLOW.value):
        return ResolutionResult(
            decision_type    = DecisionType.ALLOW_A_TO_B,
            selected_request = request_a,
            reason_code      = ReasonCode.USER_PREFERENCE,
        )

    # ── Priority 3: User A prefers their outgoing call ───────────────────────
    if pref_a == ReciprocalCallPreference.PREFER_OUTGOING.value:
        return ResolutionResult(
            decision_type    = DecisionType.ALLOW_A_TO_B,
            selected_request = request_a,
            reason_code      = ReasonCode.USER_PREFERENCE,
        )

    # ── Priority 4: User B prefers their outgoing call ───────────────────────
    if pref_b == ReciprocalCallPreference.PREFER_OUTGOING.value:
        return ResolutionResult(
            decision_type    = DecisionType.ALLOW_B_TO_A,
            selected_request = request_b,
            reason_code      = ReasonCode.USER_PREFERENCE,
        )

    # ── Priority 5: User A prefers incoming (i.e. B→A) ──────────────────────
    if pref_a == ReciprocalCallPreference.PREFER_INCOMING.value:
        return ResolutionResult(
            decision_type    = DecisionType.ALLOW_B_TO_A,
            selected_request = request_b,
            reason_code      = ReasonCode.USER_PREFERENCE,
        )

    # ── Priority 6: User B prefers incoming (i.e. A→B) ──────────────────────
    if pref_b == ReciprocalCallPreference.PREFER_INCOMING.value:
        return ResolutionResult(
            decision_type    = DecisionType.ALLOW_A_TO_B,
            selected_request = request_a,
            reason_code      = ReasonCode.USER_PREFERENCE,
        )

    # ── Priority 7: Default — ask the user ───────────────────────────────────
    return ResolutionResult(
        decision_type    = DecisionType.ASK_USER,
        selected_request = None,
        reason_code      = ReasonCode.DEFAULT_POLICY,
    )
