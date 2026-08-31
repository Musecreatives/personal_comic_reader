"""Tests for the shaddai-sync API. Run with `pytest` from this directory
(needs `pip install -r requirements.txt pytest httpx` first).
"""

import os
import tempfile

import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def client():
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    os.environ["SYNC_DB_PATH"] = path
    os.environ["SYNC_INVITE_CODE"] = "test-invite"

    import importlib

    import main as main_module

    importlib.reload(main_module)
    main_module.init_db()

    with TestClient(main_module.app) as c:
        yield c

    os.remove(path)


def register(client, username="paul", password="hunter2222", invite="test-invite"):
    return client.post(
        "/auth/register",
        json={"username": username, "password": password, "invite_code": invite},
    )


def test_register_requires_correct_invite_code(client):
    res = register(client, invite="wrong-code")
    assert res.status_code == 403


def test_register_rejects_short_passwords(client):
    res = register(client, password="short")
    assert res.status_code == 400


def test_register_then_login_roundtrip(client):
    res = register(client)
    assert res.status_code == 200
    token = res.json()["token"]
    assert token

    res = client.post(
        "/auth/login", json={"username": "paul", "password": "hunter2222"}
    )
    assert res.status_code == 200
    assert res.json()["username"] == "paul"


def test_register_rejects_duplicate_username(client):
    register(client)
    res = register(client)
    assert res.status_code == 409


def test_login_rejects_wrong_password(client):
    register(client)
    res = client.post(
        "/auth/login", json={"username": "paul", "password": "wrong-password"}
    )
    assert res.status_code == 401


def test_me_requires_bearer_token(client):
    res = client.get("/auth/me")
    assert res.status_code == 401


def test_me_returns_the_signed_in_username(client):
    token = register(client).json()["token"]
    res = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert res.status_code == 200
    assert res.json()["username"] == "paul"


def test_logout_invalidates_the_token(client):
    token = register(client).json()["token"]
    headers = {"Authorization": f"Bearer {token}"}
    client.post("/auth/logout", headers=headers)
    res = client.get("/auth/me", headers=headers)
    assert res.status_code == 401


def test_push_then_pull_roundtrips_a_record(client):
    token = register(client).json()["token"]
    headers = {"Authorization": f"Bearer {token}"}

    push = client.put(
        "/records/history",
        headers=headers,
        json=[
            {
                "record_id": "book-1",
                "data": {"bookTitle": "Issue 1"},
                "updated_at": "2026-08-30T00:00:00.000Z",
                "deleted": False,
            }
        ],
    )
    assert push.status_code == 200
    assert push.json()["records"][0]["record_id"] == "book-1"

    pull = client.get("/records/history", headers=headers)
    assert pull.status_code == 200
    assert pull.json()["records"][0]["data"]["bookTitle"] == "Issue 1"


def test_push_is_last_write_wins_by_updated_at(client):
    token = register(client).json()["token"]
    headers = {"Authorization": f"Bearer {token}"}

    client.put(
        "/records/history",
        headers=headers,
        json=[
            {
                "record_id": "book-1",
                "data": {"bookTitle": "Newer"},
                "updated_at": "2026-08-30T12:00:00.000Z",
                "deleted": False,
            }
        ],
    )
    # An older write for the same record arrives second (e.g. a device
    # that was offline) - it must not clobber the newer one.
    client.put(
        "/records/history",
        headers=headers,
        json=[
            {
                "record_id": "book-1",
                "data": {"bookTitle": "Stale"},
                "updated_at": "2026-08-30T06:00:00.000Z",
                "deleted": False,
            }
        ],
    )

    pull = client.get("/records/history", headers=headers)
    assert pull.json()["records"][0]["data"]["bookTitle"] == "Newer"


def test_pull_since_only_returns_records_updated_after_the_given_time(client):
    token = register(client).json()["token"]
    headers = {"Authorization": f"Bearer {token}"}

    client.put(
        "/records/history",
        headers=headers,
        json=[
            {
                "record_id": "book-1",
                "data": {"bookTitle": "Old"},
                "updated_at": "2026-08-29T00:00:00.000Z",
                "deleted": False,
            },
            {
                "record_id": "book-2",
                "data": {"bookTitle": "New"},
                "updated_at": "2026-08-31T00:00:00.000Z",
                "deleted": False,
            },
        ],
    )

    pull = client.get(
        "/records/history?since=2026-08-30T00:00:00.000Z", headers=headers
    )
    ids = [r["record_id"] for r in pull.json()["records"]]
    assert ids == ["book-2"]


def test_records_are_isolated_per_user(client):
    token_a = register(client, username="paul").json()["token"]
    token_b = register(client, username="friend").json()["token"]

    client.put(
        "/records/history",
        headers={"Authorization": f"Bearer {token_a}"},
        json=[
            {
                "record_id": "book-1",
                "data": {"bookTitle": "Paul's read"},
                "updated_at": "2026-08-30T00:00:00.000Z",
                "deleted": False,
            }
        ],
    )

    pull_b = client.get(
        "/records/history", headers={"Authorization": f"Bearer {token_b}"}
    )
    assert pull_b.json()["records"] == []


def test_healthz(client):
    res = client.get("/healthz")
    assert res.status_code == 200
    assert res.json() == {"ok": True}
