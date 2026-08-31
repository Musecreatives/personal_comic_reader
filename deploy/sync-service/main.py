"""shaddai-sync: a small auth + generic per-user record sync API for
Shaddai Reader (History/Collections/Appearance/Reader Settings/Stats).

Deliberately minimal for its actual scale (a couple of accounts on a
private Tailscale network, not a public multi-tenant service):

- Opaque bearer tokens in a `sessions` table, not JWTs - trivially
  revocable (delete the row), and this app already has no JWT-decode
  dependency anywhere, so this matches its existing hand-rolled-auth
  conventions rather than introducing a new one.
- One generic `sync_records` table (user_id, resource, record_id, data,
  updated_at) instead of a bespoke table per feature - the Flutter client
  already hand-writes toJson()/fromJson() for every model it wants to
  sync, so the server just stores whatever JSON blob it's handed. Adding
  a new synced feature later (Collections, Appearance, ...) needs zero
  schema changes, only a new `resource` string.
- SQLite, synchronous, one connection per request. At this scale (a
  couple of users) this is simpler and more debuggable than an async
  driver or a connection pool, and avoids yet another moving part.

Deployment note: the SQLite file backing this MUST live outside
/mnt/media-pool. That mount had two separate hardware incidents in five
days (see ROADMAP.md) that corrupted Kavita's and Kapowarr's databases -
this service's data directory is meant to be bind-mounted from the
server's root disk instead (see docker-compose.snippet.yml).
"""

from __future__ import annotations

import os
import secrets
import sqlite3
import time
from contextlib import asynccontextmanager, contextmanager
from typing import AsyncIterator, Iterator, Optional

import bcrypt
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel

DB_PATH = os.environ.get("SYNC_DB_PATH", "/data/sync.db")
INVITE_CODE = os.environ.get("SYNC_INVITE_CODE")


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    conn.row_factory = sqlite3.Row
    return conn


@contextmanager
def db() -> Iterator[sqlite3.Connection]:
    conn = _connect()
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db() -> None:
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    with db() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                created_at REAL NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS sessions (
                token TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id),
                created_at REAL NOT NULL,
                last_seen REAL NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS sync_records (
                user_id INTEGER NOT NULL REFERENCES users(id),
                resource TEXT NOT NULL,
                record_id TEXT NOT NULL,
                data TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (user_id, resource, record_id)
            )
            """
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_sync_records_lookup "
            "ON sync_records (user_id, resource, updated_at)"
        )


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    init_db()
    yield


app = FastAPI(title="shaddai-sync", lifespan=lifespan)


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------


class RegisterRequest(BaseModel):
    username: str
    password: str
    invite_code: str


class LoginRequest(BaseModel):
    username: str
    password: str


class TokenResponse(BaseModel):
    token: str
    username: str


def _issue_session(conn: sqlite3.Connection, user_id: int) -> str:
    token = secrets.token_urlsafe(32)
    now = time.time()
    conn.execute(
        "INSERT INTO sessions (token, user_id, created_at, last_seen) VALUES (?, ?, ?, ?)",
        (token, user_id, now, now),
    )
    return token


@app.post("/auth/register", response_model=TokenResponse)
def register(body: RegisterRequest) -> TokenResponse:
    if not INVITE_CODE or not secrets.compare_digest(body.invite_code, INVITE_CODE):
        raise HTTPException(status_code=403, detail="Invalid invite code")
    if not body.username.strip() or len(body.password) < 8:
        raise HTTPException(
            status_code=400, detail="Username required, password must be 8+ characters"
        )

    password_hash = bcrypt.hashpw(body.password.encode(), bcrypt.gensalt()).decode()
    with db() as conn:
        try:
            cur = conn.execute(
                "INSERT INTO users (username, password_hash, created_at) VALUES (?, ?, ?)",
                (body.username, password_hash, time.time()),
            )
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=409, detail="Username already taken")
        token = _issue_session(conn, cur.lastrowid)
    return TokenResponse(token=token, username=body.username)


@app.post("/auth/login", response_model=TokenResponse)
def login(body: LoginRequest) -> TokenResponse:
    with db() as conn:
        row = conn.execute(
            "SELECT id, password_hash FROM users WHERE username = ?", (body.username,)
        ).fetchone()
        if row is None or not bcrypt.checkpw(
            body.password.encode(), row["password_hash"].encode()
        ):
            raise HTTPException(status_code=401, detail="Invalid username or password")
        token = _issue_session(conn, row["id"])
    return TokenResponse(token=token, username=body.username)


def current_user(authorization: Optional[str] = Header(None)) -> tuple[int, str]:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    with db() as conn:
        row = conn.execute(
            """
            SELECT users.id AS user_id, users.username AS username
            FROM sessions JOIN users ON users.id = sessions.user_id
            WHERE sessions.token = ?
            """,
            (token,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=401, detail="Invalid or expired session")
        conn.execute(
            "UPDATE sessions SET last_seen = ? WHERE token = ?", (time.time(), token)
        )
    return row["user_id"], row["username"]


@app.post("/auth/logout")
def logout(authorization: Optional[str] = Header(None)) -> dict:
    if authorization and authorization.startswith("Bearer "):
        token = authorization.removeprefix("Bearer ").strip()
        with db() as conn:
            conn.execute("DELETE FROM sessions WHERE token = ?", (token,))
    return {"ok": True}


class MeResponse(BaseModel):
    username: str


@app.get("/auth/me", response_model=MeResponse)
def me(user: tuple[int, str] = Depends(current_user)) -> MeResponse:
    return MeResponse(username=user[1])


# ---------------------------------------------------------------------------
# Generic record sync
# ---------------------------------------------------------------------------


class SyncRecord(BaseModel):
    record_id: str
    data: dict
    updated_at: str
    deleted: bool = False


class PullResponse(BaseModel):
    records: list[SyncRecord]


@app.get("/records/{resource}", response_model=PullResponse)
def pull_records(
    resource: str,
    since: str = "",
    user: tuple[int, str] = Depends(current_user),
) -> PullResponse:
    user_id, _ = user
    with db() as conn:
        if since:
            rows = conn.execute(
                """
                SELECT record_id, data, updated_at, deleted FROM sync_records
                WHERE user_id = ? AND resource = ? AND updated_at > ?
                ORDER BY updated_at ASC
                """,
                (user_id, resource, since),
            ).fetchall()
        else:
            rows = conn.execute(
                """
                SELECT record_id, data, updated_at, deleted FROM sync_records
                WHERE user_id = ? AND resource = ? AND deleted = 0
                ORDER BY updated_at ASC
                """,
                (user_id, resource),
            ).fetchall()

    import json

    return PullResponse(
        records=[
            SyncRecord(
                record_id=r["record_id"],
                data=json.loads(r["data"]),
                updated_at=r["updated_at"],
                deleted=bool(r["deleted"]),
            )
            for r in rows
        ]
    )


@app.put("/records/{resource}", response_model=PullResponse)
def push_records(
    resource: str,
    records: list[SyncRecord],
    user: tuple[int, str] = Depends(current_user),
) -> PullResponse:
    import json

    user_id, _ = user
    with db() as conn:
        for record in records:
            existing = conn.execute(
                """
                SELECT updated_at FROM sync_records
                WHERE user_id = ? AND resource = ? AND record_id = ?
                """,
                (user_id, resource, record.record_id),
            ).fetchone()
            # Last-write-wins by updated_at - an older incoming write than
            # what the server already has is dropped, not overwritten, so
            # a device reconciling a stale local copy can't clobber a
            # newer write from elsewhere.
            if existing is not None and existing["updated_at"] >= record.updated_at:
                continue
            conn.execute(
                """
                INSERT INTO sync_records (user_id, resource, record_id, data, updated_at, deleted)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(user_id, resource, record_id)
                DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at,
                              deleted = excluded.deleted
                """,
                (
                    user_id,
                    resource,
                    record.record_id,
                    json.dumps(record.data),
                    record.updated_at,
                    int(record.deleted),
                ),
            )

        rows = conn.execute(
            """
            SELECT record_id, data, updated_at, deleted FROM sync_records
            WHERE user_id = ? AND resource = ? AND deleted = 0
            ORDER BY updated_at ASC
            """,
            (user_id, resource),
        ).fetchall()

    return PullResponse(
        records=[
            SyncRecord(
                record_id=r["record_id"],
                data=json.loads(r["data"]),
                updated_at=r["updated_at"],
                deleted=bool(r["deleted"]),
            )
            for r in rows
        ]
    )


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True}
