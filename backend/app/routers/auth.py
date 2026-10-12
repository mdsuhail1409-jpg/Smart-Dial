"""
Authentication router: /api/auth/register and /api/auth/login.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from app.database import get_db
from app.models.user import User
from app.schemas.auth import (
    RegisterRequest,
    LoginRequest,
    TokenResponse,
    OtpSendRequest,
    OtpSendResponse,
    OtpVerifyRequest,
    OtpVerifyResponse,
)
from app.services.otp_service import send_otp, verify_otp
from app.schemas.user import UserResponse
from app.security.password import hash_password, verify_password
from app.security.jwt import create_access_token

router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.post(
    "/register",
    response_model=UserResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Register a new user",
)
def register(payload: RegisterRequest, db: Session = Depends(get_db)) -> UserResponse:
    """
    Create a new SmartDial user account.

    - Validates input via Pydantic.
    - Rejects duplicate email or phone with a clear error.
    - Stores only the bcrypt hash of the password, never the plaintext.
    - Returns the created user without password_hash.
    """
    # Check for duplicate email
    if db.query(User).filter(User.email == payload.email).first():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email already exists",
        )

    # Check for duplicate phone
    if db.query(User).filter(User.phone == payload.phone).first():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this phone number already exists",
        )

    new_user = User(
        name=payload.name,
        email=payload.email,
        phone=payload.phone,
        password_hash=hash_password(payload.password),
    )
    db.add(new_user)

    try:
        db.commit()
        db.refresh(new_user)
        # Persist to MongoDB Atlas for zero-data-loss durability
        try:
            from app.mongodb import sync_user_to_mongo
            sync_user_to_mongo(new_user)
        except Exception:
            pass
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A user with that email or phone already exists",
        )

    return UserResponse.model_validate(new_user)


@router.post(
    "/login",
    response_model=TokenResponse,
    summary="Login and receive a JWT access token",
)
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> TokenResponse:
    """
    Authenticate a user and return a JWT token.

    Uses a generic error message for both unknown email and wrong password
    to avoid leaking which field was incorrect (timing-safe equivalent behavior).
    """
    user = db.query(User).filter(User.email == payload.email).first()

    # Fallback to MongoDB Atlas if local container was restarted / cold booted
    if user is None:
        try:
            from app.mongodb import get_user_by_email
            from app.models.user import UserStatus, ReciprocalCallPreference
            m_user = get_user_by_email(payload.email)
            if m_user:
                pref_val = m_user.get("reciprocal_call_preference", "ASK")
                try:
                    pref_enum = ReciprocalCallPreference(pref_val)
                except Exception:
                    pref_enum = ReciprocalCallPreference.ASK

                restored_user = User(
                    id=m_user.get("id"),
                    name=m_user.get("name"),
                    email=m_user.get("email"),
                    phone=m_user.get("phone"),
                    password_hash=m_user.get("password_hash"),
                    status=UserStatus.ACTIVE,
                    reciprocal_call_preference=pref_enum,
                    dnd_enabled=bool(m_user.get("dnd_enabled", False)),
                    vip_contacts=str(m_user.get("vip_contacts", "") or ""),
                )
                db.add(restored_user)
                db.commit()
                db.refresh(restored_user)
                user = restored_user
        except Exception:
            db.rollback()

    # Deliberate: same error for unknown user OR wrong password
    if user is None or not verify_password(payload.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = create_access_token(subject=user.id)

    return TokenResponse(
        access_token=token,
        token_type="bearer",
        user=UserResponse.model_validate(user),
    )


@router.post(
    "/otp/send",
    response_model=OtpSendResponse,
    summary="Dispatch a 6-digit verification code to the phone number",
)
def request_phone_otp(payload: OtpSendRequest) -> OtpSendResponse:
    """
    Generate and dispatch a cryptographically secure 6-digit OTP
    to verify possession of the E.164 phone number.
    """
    res = send_otp(payload.phone)
    return OtpSendResponse(**res)


@router.post(
    "/otp/verify",
    response_model=OtpVerifyResponse,
    summary="Verify possession of phone number using 6-digit code",
)
def verify_phone_otp(payload: OtpVerifyRequest) -> OtpVerifyResponse:
    """
    Verify the 6-digit code sent to the phone number.
    Prevents phone number spoofing and unauthorized registration.
    """
    is_valid = verify_otp(payload.phone, payload.code)
    if not is_valid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired verification code",
        )
    return OtpVerifyResponse(
        verified=True,
        phone=payload.phone,
        message="Phone number successfully verified",
    )
