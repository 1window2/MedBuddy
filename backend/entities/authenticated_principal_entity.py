# File Name: authenticated_principal_entity.py
# Role: Maps verified external authentication claims to immutable internal ownership and provider metadata.
"""Authenticated request identity used by backend authorization controls."""

import hashlib
from datetime import UTC, datetime

from pydantic import BaseModel, ConfigDict

from entities.patient_hash_entity import DEFAULT_PATIENT_HASH


# Class Name: AuthenticatedPrincipal
# Role:
# - Represents a verified external identity mapped to a MedBuddy user key.
# Responsibilities:
# - Derive ownership only from verified issuer/subject claims and retain provider and recent-authentication evidence.
# Attributes:
# - user_hash (str): Account ownership scope for the operation.
# - expires_at (datetime | None): Expiry of the verified token; None when the
#   identity carries no expiry (authentication disabled) or the claim is unusable.
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
    expires_at: datetime | None = None

    # Function Name: from_verified_claims
    # Description:
    # - Derives an internal user hash from verified issuer/subject claims and records provider, contact and authentication-time metadata.
    # Parameters:
    # - claims (dict[str, object]): Token claims already verified by the authentication boundary.
    # Returns:
    # - Immutable principal; ValueError when required identity or authentication-time claims are invalid.
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
            expires_at=cls._expiry_from_claim(claims.get("exp")),
        )

    # Function Name: _expiry_from_claim
    # Description:
    # - Reads the token expiry for long-lived connections. The verifier has already
    #   rejected an expired token, so an absent or malformed claim yields None instead
    #   of failing a request that only needs the identity.
    # Parameters:
    # - value (object): The verified token's `exp` claim, in seconds since the epoch.
    # Returns:
    # - Timezone-aware expiry, or None when the claim cannot be read as a time.
    @staticmethod
    def _expiry_from_claim(value: object) -> datetime | None:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return None
        try:
            return datetime.fromtimestamp(float(value), tz=UTC)
        except (OverflowError, OSError, ValueError):
            return None

    # Function Name: development_principal
    # Description:
    # - Builds the explicit authentication-disabled identity used by local development.
    # Parameters:
    # - None.
    # Returns:
    # - Development principal with the default patient scope and bypass flag.
    @classmethod
    def development_principal(cls) -> "AuthenticatedPrincipal":
        return cls(
            subject="development-user",
            issuer="medbuddy-development",
            user_hash=DEFAULT_PATIENT_HASH,
            authentication_disabled=True,
        )
