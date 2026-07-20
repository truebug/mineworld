"""Platform service configuration (env SSOT; SQLite default, Postgres later)."""

from __future__ import annotations

import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SQLITE = REPO_ROOT / "mw_platform" / "data" / "platform.sqlite"


def _env_bool(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in ("1", "true", "yes", "on")


def db_url() -> str:
    """Database URL. sqlite:///path or postgres:// (future)."""
    return os.environ.get("MW_PLATFORM_DB_URL", f"sqlite:///{DEFAULT_SQLITE}")


def auth_enabled() -> bool:
    """When false, skip portal gate (local dev only)."""
    return _env_bool("MW_PLATFORM_AUTH", True)


def token_ttl_hours() -> int:
    return int(os.environ.get("MW_PLATFORM_TOKEN_TTL_H", "168"))


def secret_key() -> str:
    """HMAC/pepper for tokens; dev default is not for production."""
    return os.environ.get("MW_PLATFORM_SECRET", "mineworld-dev-secret-change-me")


def admin_key() -> str | None:
    """Optional static admin key for POST /api/platform/admin/players."""
    return os.environ.get("MW_PLATFORM_ADMIN_KEY")


def bind_host() -> str:
    return os.environ.get("MW_PLATFORM_HOST", "127.0.0.1")


def bind_port() -> int:
    return int(os.environ.get("MW_PLATFORM_PORT", "8090"))
