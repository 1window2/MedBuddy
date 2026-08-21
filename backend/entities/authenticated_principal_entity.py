"""Authenticated request identity used by backend authorization controls."""

import hashlib
from datetime import UTC, datetime

from pydantic import BaseModel, ConfigDict

from entities.patient_hash_entity import DEFAULT_PATIENT_HASH


class AuthenticatedPrincipal(BaseModel):
    """Represents a verified external identity mapped to a MedBuddy user key."""

    model_config = ConfigDict(frozen=True)

    subject: str
    issuer: str
    user_hash: str
    email: str | None = None
    email_verified: bool = False
    phone_number: str | None = None
    sign_in_provider: str = ""
    anonymous: bool = False
    authentication_disabled: bool = False
    authenticated_at: datetime | None = None

    @classmethod
    def from_verified_claims(
        cls,
        claims: dict[str, object],
    ) -> "AuthenticatedPrincipal":
        subject = str(claims.get("uid") or claims.get("sub") or "").strip()
        issuer = str(claims.get("iss") or "").strip()
        if not subject or not issuer:
            raise ValueError("Verified token is missing identity claims.")

        identity_digest = hashlib.sha256(
            f"{issuer}\0{subject}".encode("utf-8")
        ).hexdigest()[:32]
        email_value = claims.get("email")
        email = str(email_value).strip() if email_value else None
        phone_value = claims.get("phone_number")
        phone_number = str(phone_value).strip() if phone_value else None
        firebase_claim = claims.get("firebase")
        sign_in_provider = ""
        if isinstance(firebase_claim, dict):
            sign_in_provider = str(
                firebase_claim.get("sign_in_provider") or ""
            ).strip()
        auth_time_value = claims.get("auth_time")
        authenticated_at: datetime | None = None
        if auth_time_value is not None:
            if isinstance(auth_time_value, bool) or not isinstance(
                auth_time_value,
                (int, float),
            ):
                raise ValueError("Verified token has an invalid auth_time claim.")
            try:
                authenticated_at = datetime.fromtimestamp(
                    float(auth_time_value),
                    tz=UTC,
                )
            except (OverflowError, OSError, ValueError) as exc:
                raise ValueError(
                    "Verified token has an invalid auth_time claim."
                ) from exc
        return cls(
            subject=subject,
            issuer=issuer,
            user_hash=f"usr_{identity_digest}",
            email=email,
            email_verified=claims.get("email_verified") is True,
            phone_number=phone_number,
            sign_in_provider=sign_in_provider,
            anonymous=sign_in_provider == "anonymous",
            authenticated_at=authenticated_at,
        )

    @classmethod
    def development_principal(cls) -> "AuthenticatedPrincipal":
        return cls(
            subject="development-user",
            issuer="medbuddy-development",
            user_hash=DEFAULT_PATIENT_HASH,
            authentication_disabled=True,
        )
