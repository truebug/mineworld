"""Player + token persistence — SQLite v0; URL-swappable for Postgres."""

from __future__ import annotations

import sqlite3
from abc import ABC, abstractmethod
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterator
from urllib.parse import urlparse

from mw_platform import auth as auth_mod
from mw_platform.config import db_url, token_ttl_hours


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(dt: datetime) -> str:
    return dt.replace(microsecond=0).isoformat()


@dataclass(frozen=True)
class Player:
    player_id: str
    display_name: str
    accent: str
    active: bool = True


class PlayerStore(ABC):
    """Storage contract — implement for Postgres without changing HTTP handlers."""

    @abstractmethod
    def ensure_schema(self) -> None: ...

    @abstractmethod
    def get_player(self, player_id: str) -> Player | None: ...

    @abstractmethod
    def create_player(
        self,
        player_id: str,
        display_name: str,
        password: str,
        *,
        accent: str = "#4aa3ff",
    ) -> Player: ...

    @abstractmethod
    def verify_password(self, player_id: str, password: str) -> Player | None: ...

    @abstractmethod
    def issue_token(self, player_id: str) -> str: ...

    @abstractmethod
    def resolve_token(self, token: str) -> Player | None: ...

    @abstractmethod
    def revoke_token(self, token: str) -> None: ...

    @abstractmethod
    def list_players(self) -> list[Player]: ...


class SQLitePlayerStore(PlayerStore):
    """SQLite backend (Phase A default)."""

    def __init__(self, path: Path) -> None:
        self._path = path
        self._path.parent.mkdir(parents=True, exist_ok=True)

    @contextmanager
    def _conn(self) -> Iterator[sqlite3.Connection]:
        conn = sqlite3.connect(self._path)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()

    def ensure_schema(self) -> None:
        with self._conn() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS players (
                    player_id TEXT PRIMARY KEY,
                    display_name TEXT NOT NULL,
                    password_hash TEXT NOT NULL,
                    accent TEXT NOT NULL DEFAULT '#4aa3ff',
                    active INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS auth_tokens (
                    token TEXT PRIMARY KEY,
                    player_id TEXT NOT NULL REFERENCES players(player_id),
                    expires_at TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_auth_tokens_player
                    ON auth_tokens(player_id);
                CREATE TABLE IF NOT EXISTS scores (
                    session_id TEXT PRIMARY KEY,
                    player_id TEXT NOT NULL,
                    display_name TEXT NOT NULL DEFAULT '',
                    level_id TEXT NOT NULL,
                    task_id TEXT,
                    outcome TEXT NOT NULL,
                    duration_sim_s REAL NOT NULL DEFAULT 0,
                    points INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    space_id TEXT,
                    route_kind TEXT NOT NULL DEFAULT 'mineworld_level'
                );
                CREATE INDEX IF NOT EXISTS idx_scores_player
                    ON scores(player_id);
                CREATE INDEX IF NOT EXISTS idx_scores_points
                    ON scores(points DESC);
                CREATE TABLE IF NOT EXISTS identity_links (
                    issuer TEXT NOT NULL,
                    external_sub TEXT NOT NULL,
                    player_id TEXT NOT NULL REFERENCES players(player_id),
                    created_at TEXT NOT NULL,
                    PRIMARY KEY (issuer, external_sub)
                );
                CREATE INDEX IF NOT EXISTS idx_identity_links_player
                    ON identity_links(player_id);
                """
            )
            # E3: optional space_id on existing DBs (CREATE IF NOT EXISTS won't add cols).
            cols = {
                str(r[1])
                for r in conn.execute("PRAGMA table_info(scores)").fetchall()
            }
            if "space_id" not in cols:
                conn.execute("ALTER TABLE scores ADD COLUMN space_id TEXT")
            if "route_kind" not in cols:
                conn.execute(
                    "ALTER TABLE scores ADD COLUMN route_kind TEXT NOT NULL DEFAULT 'mineworld_level'"
                )

    def record_score(
        self,
        *,
        session_id: str,
        player_id: str,
        level_id: str,
        outcome: str,
        points: int,
        duration_sim_s: float = 0.0,
        task_id: str | None = None,
        display_name: str | None = None,
        space_id: str | None = None,
        route_kind: str | None = None,
    ) -> dict[str, Any]:
        """Idempotent upsert by session_id. Returns {created, row}."""
        sid = session_id.strip()
        pid = player_id.strip()
        if not sid or not pid:
            raise ValueError("session_id and player_id required")
        name = (display_name or "").strip()
        if not name:
            p = self.get_player(pid)
            name = p.display_name if p else pid
        space = (space_id or "").strip() or None
        rk = (route_kind or "mineworld_level").strip() or "mineworld_level"
        now = _iso(_utc_now())
        with self._conn() as conn:
            existing = conn.execute(
                "SELECT session_id, points FROM scores WHERE session_id = ?",
                (sid,),
            ).fetchone()
            if existing is not None:
                row = conn.execute(
                    """
                    SELECT session_id, player_id, display_name, level_id, task_id,
                           outcome, duration_sim_s, points, created_at, space_id, route_kind
                    FROM scores WHERE session_id = ?
                    """,
                    (sid,),
                ).fetchone()
                return {"created": False, "row": dict(row) if row else {}}
            conn.execute(
                """
                INSERT INTO scores (
                    session_id, player_id, display_name, level_id, task_id,
                    outcome, duration_sim_s, points, created_at, space_id, route_kind
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    sid,
                    pid,
                    name,
                    level_id,
                    task_id,
                    outcome,
                    float(duration_sim_s),
                    int(points),
                    now,
                    space,
                    rk,
                ),
            )
            row = conn.execute(
                """
                SELECT session_id, player_id, display_name, level_id, task_id,
                       outcome, duration_sim_s, points, created_at, space_id, route_kind
                FROM scores WHERE session_id = ?
                """,
                (sid,),
            ).fetchone()
        return {"created": True, "row": dict(row) if row else {}}

    def leaderboard(self, *, limit: int = 10, level_id: str | None = None) -> list[dict[str, Any]]:
        """Aggregate points per player; optional filter by level_id (A2)."""
        lim = max(1, min(50, int(limit)))
        lid = (level_id or "").strip()
        with self._conn() as conn:
            if lid:
                rows = conn.execute(
                    """
                    SELECT player_id,
                           MAX(display_name) AS display_name,
                           SUM(points) AS total_points,
                           COUNT(*) AS runs,
                           MIN(CASE WHEN outcome = 'success' THEN duration_sim_s END)
                             AS best_duration_sim_s
                    FROM scores
                    WHERE points > 0 AND level_id = ?
                    GROUP BY player_id
                    ORDER BY total_points DESC,
                             best_duration_sim_s ASC NULLS LAST,
                             runs ASC
                    LIMIT ?
                    """,
                    (lid, lim),
                ).fetchall()
            else:
                rows = conn.execute(
                    """
                    SELECT player_id,
                           MAX(display_name) AS display_name,
                           SUM(points) AS total_points,
                           COUNT(*) AS runs
                    FROM scores
                    WHERE points > 0
                    GROUP BY player_id
                    ORDER BY total_points DESC, runs ASC
                    LIMIT ?
                    """,
                    (lim,),
                ).fetchall()
        out = [dict(r) for r in rows]
        if lid:
            for row in out:
                row["level_id"] = lid
        return out

    def player_stats(self, player_id: str) -> dict[str, Any]:
        """Totals for one player."""
        with self._conn() as conn:
            row = conn.execute(
                """
                SELECT COALESCE(SUM(points), 0) AS total_points,
                       COUNT(*) AS runs,
                       COALESCE(SUM(CASE WHEN outcome = 'success' THEN 1 ELSE 0 END), 0) AS wins
                FROM scores
                WHERE player_id = ?
                """,
                (player_id.strip(),),
            ).fetchone()
        if row is None:
            return {"total_points": 0, "runs": 0, "wins": 0}
        return {
            "total_points": int(row["total_points"]),
            "runs": int(row["runs"]),
            "wins": int(row["wins"]),
        }

    def player_scores(self, player_id: str, *, limit: int = 20) -> list[dict[str, Any]]:
        """Recent score rows for one player (newest first)."""
        lim = max(1, min(100, int(limit)))
        with self._conn() as conn:
            rows = conn.execute(
                """
                SELECT session_id, level_id, task_id, outcome, duration_sim_s,
                       points, created_at, space_id, route_kind
                FROM scores
                WHERE player_id = ?
                ORDER BY created_at DESC
                LIMIT ?
                """,
                (player_id.strip(), lim),
            ).fetchall()
        return [dict(r) for r in rows]

    def _row_to_player(self, row: sqlite3.Row | None) -> Player | None:
        if row is None:
            return None
        return Player(
            player_id=str(row["player_id"]),
            display_name=str(row["display_name"]),
            accent=str(row["accent"]),
            active=bool(row["active"]),
        )

    def get_player(self, player_id: str) -> Player | None:
        with self._conn() as conn:
            row = conn.execute(
                "SELECT player_id, display_name, accent, active FROM players WHERE player_id = ?",
                (player_id,),
            ).fetchone()
        return self._row_to_player(row)

    def create_player(
        self,
        player_id: str,
        display_name: str,
        password: str,
        *,
        accent: str = "#4aa3ff",
    ) -> Player:
        pid = player_id.strip()
        if not pid:
            raise ValueError("player_id required")
        if self.get_player(pid) is not None:
            raise ValueError("player_id already exists")
        ph = auth_mod.hash_password(password)
        now = _iso(_utc_now())
        with self._conn() as conn:
            conn.execute(
                """
                INSERT INTO players (player_id, display_name, password_hash, accent, active, created_at)
                VALUES (?, ?, ?, ?, 1, ?)
                """,
                (pid, display_name.strip() or pid, ph, accent, now),
            )
        player = self.get_player(pid)
        assert player is not None
        return player

    def verify_password(self, player_id: str, password: str) -> Player | None:
        with self._conn() as conn:
            row = conn.execute(
                "SELECT password_hash FROM players WHERE player_id = ? AND active = 1",
                (player_id.strip(),),
            ).fetchone()
        if row is None:
            return None
        if not auth_mod.verify_password(password, str(row["password_hash"])):
            return None
        return self.get_player(player_id.strip())

    def issue_token(self, player_id: str) -> str:
        token = auth_mod.new_token()
        exp = _utc_now() + timedelta(hours=token_ttl_hours())
        now = _iso(_utc_now())
        with self._conn() as conn:
            conn.execute(
                """
                INSERT INTO auth_tokens (token, player_id, expires_at, created_at)
                VALUES (?, ?, ?, ?)
                """,
                (token, player_id, _iso(exp), now),
            )
        return token

    def resolve_token(self, token: str) -> Player | None:
        if not token:
            return None
        with self._conn() as conn:
            row = conn.execute(
                """
                SELECT t.player_id, t.expires_at, p.display_name, p.accent, p.active
                FROM auth_tokens t
                JOIN players p ON p.player_id = t.player_id
                WHERE t.token = ?
                """,
                (token.strip(),),
            ).fetchone()
        if row is None or not row["active"]:
            return None
        try:
            exp = datetime.fromisoformat(str(row["expires_at"]))
            if exp.tzinfo is None:
                exp = exp.replace(tzinfo=timezone.utc)
        except ValueError:
            return None
        if _utc_now() >= exp:
            self.revoke_token(token)
            return None
        return Player(
            player_id=str(row["player_id"]),
            display_name=str(row["display_name"]),
            accent=str(row["accent"]),
            active=True,
        )

    def revoke_token(self, token: str) -> None:
        with self._conn() as conn:
            conn.execute("DELETE FROM auth_tokens WHERE token = ?", (token.strip(),))

    def list_players(self) -> list[Player]:
        with self._conn() as conn:
            rows = conn.execute(
                "SELECT player_id, display_name, accent, active FROM players ORDER BY player_id"
            ).fetchall()
        out: list[Player] = []
        for row in rows:
            p = self._row_to_player(row)
            if p is not None:
                out.append(p)
        return out

    def list_identity_links(self, player_id: str) -> list[dict[str, str]]:
        """Return external identity links for a player (E2)."""
        with self._conn() as conn:
            rows = conn.execute(
                """
                SELECT issuer, external_sub, player_id, created_at
                FROM identity_links WHERE player_id = ?
                ORDER BY issuer, external_sub
                """,
                (player_id.strip(),),
            ).fetchall()
        return [
            {
                "issuer": str(r["issuer"]),
                "external_sub": str(r["external_sub"]),
                "player_id": str(r["player_id"]),
                "created_at": str(r["created_at"]),
            }
            for r in rows
        ]

    def resolve_identity(self, issuer: str, external_sub: str) -> Player | None:
        """Lookup player by (issuer, external_sub)."""
        iss = issuer.strip().lower()
        sub = external_sub.strip()
        if not iss or not sub:
            return None
        with self._conn() as conn:
            row = conn.execute(
                """
                SELECT player_id FROM identity_links
                WHERE issuer = ? AND external_sub = ?
                """,
                (iss, sub),
            ).fetchone()
        if row is None:
            return None
        return self.get_player(str(row["player_id"]))

    def link_identity(
        self,
        *,
        player_id: str,
        issuer: str,
        external_sub: str,
    ) -> dict[str, str]:
        """Attach (issuer, external_sub) to an existing player_id.

        Raises ValueError on missing player or conflicting link.
        """
        pid = player_id.strip()
        iss = issuer.strip().lower()
        sub = external_sub.strip()
        if not pid or not iss or not sub:
            raise ValueError("player_id, issuer, external_sub required")
        if self.get_player(pid) is None:
            raise ValueError("player not found")
        existing = self.resolve_identity(iss, sub)
        if existing is not None and existing.player_id != pid:
            raise ValueError("external identity already linked to another player")
        if existing is not None and existing.player_id == pid:
            return {"issuer": iss, "external_sub": sub, "player_id": pid}
        now = _iso(_utc_now())
        with self._conn() as conn:
            conn.execute(
                """
                INSERT INTO identity_links (issuer, external_sub, player_id, created_at)
                VALUES (?, ?, ?, ?)
                """,
                (iss, sub, pid, now),
            )
        return {"issuer": iss, "external_sub": sub, "player_id": pid}

    def ensure_federated_player(
        self,
        *,
        issuer: str,
        external_sub: str,
        display_name: str | None = None,
        accent: str = "#4aa3ff",
    ) -> Player:
        """Resolve link or create fed_* player + link (E2 stub login)."""
        iss = issuer.strip().lower()
        sub = external_sub.strip()
        found = self.resolve_identity(iss, sub)
        if found is not None:
            return found
        # Stable local id: fed_<issuer>_<safe_sub>
        safe = "".join(c if c.isalnum() or c in "-_" else "_" for c in sub)[:40]
        if not safe:
            safe = "user"
        base = f"fed_{iss}_{safe}"[:64]
        pid = base
        n = 0
        while self.get_player(pid) is not None:
            n += 1
            pid = f"{base}_{n}"[:64]
        name = (display_name or "").strip() or pid
        # Random password — federated accounts login via link, not password.
        password = auth_mod.new_token()
        player = self.create_player(pid, name, password, accent=accent)
        self.link_identity(player_id=player.player_id, issuer=iss, external_sub=sub)
        return player


class PostgresPlayerStore(PlayerStore):
    """Placeholder — swap via MW_PLATFORM_DB_URL=postgres://... later."""

    def __init__(self, _url: str) -> None:
        raise NotImplementedError(
            "Postgres backend not implemented yet; set MW_PLATFORM_DB_URL=sqlite:///path"
        )

    def ensure_schema(self) -> None:
        raise NotImplementedError

    def get_player(self, player_id: str) -> Player | None:
        raise NotImplementedError

    def create_player(
        self,
        player_id: str,
        display_name: str,
        password: str,
        *,
        accent: str = "#4aa3ff",
    ) -> Player:
        raise NotImplementedError

    def verify_password(self, player_id: str, password: str) -> Player | None:
        raise NotImplementedError

    def issue_token(self, player_id: str) -> str:
        raise NotImplementedError

    def resolve_token(self, token: str) -> Player | None:
        raise NotImplementedError

    def revoke_token(self, token: str) -> None:
        raise NotImplementedError

    def list_players(self) -> list[Player]:
        raise NotImplementedError

    def record_score(self, **kwargs: Any) -> dict[str, Any]:
        raise NotImplementedError

    def leaderboard(self, *, limit: int = 10, level_id: str | None = None) -> list[dict[str, Any]]:
        raise NotImplementedError

    def player_stats(self, player_id: str) -> dict[str, Any]:
        raise NotImplementedError

    def player_scores(self, player_id: str, *, limit: int = 20) -> list[dict[str, Any]]:
        raise NotImplementedError


_STORE: PlayerStore | None = None


def get_store() -> PlayerStore:
    """Singleton store from MW_PLATFORM_DB_URL."""
    global _STORE
    if _STORE is not None:
        return _STORE
    url = db_url()
    parsed = urlparse(url)
    scheme = parsed.scheme.lower()
    if scheme in ("sqlite", "file"):
        path = Path(parsed.path)
        if scheme == "file" or (len(parsed.path) > 0 and parsed.netloc):
            # sqlite:////absolute/path or sqlite:///relative
            path = Path(parsed.netloc + parsed.path) if parsed.netloc else path
        _STORE = SQLitePlayerStore(path)
    elif scheme in ("postgres", "postgresql"):
        _STORE = PostgresPlayerStore(url)
    else:
        raise ValueError(f"unsupported MW_PLATFORM_DB_URL scheme: {scheme}")
    _STORE.ensure_schema()
    return _STORE


def player_to_json(p: Player) -> dict[str, Any]:
    return {
        "player_id": p.player_id,
        "display_name": p.display_name,
        "accent": p.accent,
    }


def ensure_demo_player(store: PlayerStore) -> None:
    """Seed demo/demo for local login if missing."""
    if store.get_player("demo") is None:
        store.create_player("demo", "Demo Pilot", "demo", accent="#4aa3ff")
