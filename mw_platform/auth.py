"""Password hashing and opaque session tokens (stdlib only)."""

from __future__ import annotations

import hashlib
import hmac
import secrets


def hash_password(password: str, *, iterations: int = 120_000) -> str:
    """Return pbkdf2_hmac sha256 string: salt$hexdigest."""
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return f"{salt.hex()}${iterations}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    """Verify password against stored hash."""
    try:
        salt_hex, iter_s, digest_hex = stored.split("$", 2)
        iterations = int(iter_s)
        salt = bytes.fromhex(salt_hex)
        expected = bytes.fromhex(digest_hex)
    except (ValueError, TypeError):
        return False
    got = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return hmac.compare_digest(got, expected)


def new_token() -> str:
    """Opaque bearer token."""
    return secrets.token_urlsafe(32)
