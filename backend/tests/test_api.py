"""HTTP tests for all FastAPI routes (uses in-memory SQLite via DATABASE_URL)."""

from __future__ import annotations

import os
import uuid
from datetime import datetime, timezone

import pytest

os.environ["DATABASE_URL"] = "sqlite:///:memory:"

from fastapi.testclient import TestClient

from main import app


@pytest.fixture
def client() -> TestClient:
    # Context manager triggers lifespan (init_db, seed) before requests.
    with TestClient(app) as c:
        yield c


def _unique_email() -> str:
    return f"api_test_{uuid.uuid4().hex[:10]}@example.com"


def test_register_player_and_login(client: TestClient) -> None:
    email = _unique_email()
    r = client.post(
        "/auth/register",
        json={
            "name": "Test Player",
            "email": email,
            "password": "password12",
            "role": "player",
        },
    )
    assert r.status_code == 200, r.text
    data = r.json()
    assert "access_token" in data
    assert data["user"]["email"] == email
    assert data["user"]["role"] == "player"

    r2 = client.post(
        "/auth/login",
        json={"email": email, "password": "password12"},
    )
    assert r2.status_code == 200, r2.text
    assert r2.json()["user"]["role"] == "player"


def test_register_duplicate_email(client: TestClient) -> None:
    email = _unique_email()
    body = {
        "name": "A",
        "email": email,
        "password": "password12",
        "role": "player",
    }
    assert client.post("/auth/register", json=body).status_code == 200
    r = client.post("/auth/register", json=body)
    assert r.status_code == 400
    assert "already registered" in r.json()["detail"].lower()


def test_login_invalid_credentials(client: TestClient) -> None:
    r = client.post(
        "/auth/login",
        json={"email": "nobody@example.com", "password": "wrongwrong1"},
    )
    assert r.status_code == 401


def test_me_without_token(client: TestClient) -> None:
    r = client.get("/auth/me")
    assert r.status_code == 401


def test_me_with_token(client: TestClient) -> None:
    email = _unique_email()
    reg = client.post(
        "/auth/register",
        json={
            "name": "Me Test",
            "email": email,
            "password": "password12",
            "role": "organizer",
        },
    )
    token = reg.json()["access_token"]
    r = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 200
    assert r.json()["email"] == email
    assert r.json()["role"] == "organizer"


def test_create_event_and_nearby_get_patch_bookings(client: TestClient) -> None:
    org_email = _unique_email()
    reg = client.post(
        "/auth/register",
        json={
            "name": "Org",
            "email": org_email,
            "password": "password12",
            "role": "organizer",
        },
    )
    assert reg.status_code == 200
    org_id = reg.json()["user"]["id"]

    start = datetime(2026, 6, 15, 18, 0, 0, tzinfo=timezone.utc)
    ev = client.post(
        "/events/",
        json={
            "organizer_id": org_id,
            "title": "Pickup Soccer",
            "sport_type": "Soccer",
            "lat": 37.7749,
            "long": -122.4194,
            "price": 20.0,
            "max_slots": 12,
            "start_time": start.isoformat().replace("+00:00", "Z"),
            "status": 1,
            "extra_config": {"overs": 20, "balls_per_over": 6},
        },
    )
    assert ev.status_code == 200, ev.text
    event_id = ev.json()["id"]
    assert ev.json()["extra_config"] == {"overs": 20, "balls_per_over": 6}

    nearby = client.get(
        "/events/nearby",
        params={"lat": 37.775, "long": -122.419, "radius": 50},
    )
    assert nearby.status_code == 200
    rows = nearby.json()
    assert len(rows) >= 1
    assert any(e["id"] == event_id for e in rows)
    assert "distance_km" in rows[0]

    one = client.get(f"/events/{event_id}")
    assert one.status_code == 200
    assert one.json()["title"] == "Pickup Soccer"
    assert one.json()["extra_config"] == {"overs": 20, "balls_per_over": 6}

    missing = client.get("/events/99999")
    assert missing.status_code == 404

    patch = client.patch(
        f"/events/{event_id}",
        json={"status": 3},
    )
    assert patch.status_code == 200
    assert patch.json()["status"] == 3

    bookings = client.get(f"/events/{event_id}/bookings")
    assert bookings.status_code == 200
    assert bookings.json() == []


def test_create_event_nonexistent_organizer(client: TestClient) -> None:
    start = datetime(2026, 6, 15, 18, 0, 0, tzinfo=timezone.utc)
    r = client.post(
        "/events/",
        json={
            "organizer_id": 999999,
            "title": "X",
            "sport_type": "Soccer",
            "lat": 0.0,
            "long": 0.0,
            "price": 1.0,
            "max_slots": 5,
            "start_time": start.isoformat().replace("+00:00", "Z"),
            "status": 0,
        },
    )
    assert r.status_code == 404


def test_patch_me_location_and_create_event_me(client: TestClient) -> None:
    email = _unique_email()
    reg = client.post(
        "/auth/register",
        json={
            "name": "Org Loc",
            "email": email,
            "password": "password12",
            "role": "organizer",
        },
    )
    assert reg.status_code == 200
    token = reg.json()["access_token"]

    loc = client.patch(
        "/auth/me/location",
        headers={"Authorization": f"Bearer {token}"},
        json={"lat": 40.7128, "long": -74.006},
    )
    assert loc.status_code == 200, loc.text
    assert loc.json()["last_lat"] == pytest.approx(40.7128)
    assert loc.json()["last_long"] == pytest.approx(-74.006)

    me = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200
    assert me.json()["last_lat"] == pytest.approx(40.7128)

    reg_open = datetime(2026, 6, 20, 9, 0, 0, tzinfo=timezone.utc)
    reg_close = datetime(2026, 7, 1, 19, 0, 0, tzinfo=timezone.utc)
    match_start = datetime(2026, 7, 5, 18, 0, 0, tzinfo=timezone.utc)
    ev = client.post(
        "/events/me",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "title": "My Hosted Game",
            "sport_type": "Soccer",
            "venue_name": "Riverside Pitch A",
            "description": "Bring cleats and water.",
            "duration_minutes": 90,
            "skill_level": "intermediate",
            "contact_phone": "+15551234567",
            "lat": 40.713,
            "long": -74.006,
            "price": 15.0,
            "max_slots": 10,
            "registration_start": reg_open.isoformat().replace("+00:00", "Z"),
            "registration_end": reg_close.isoformat().replace("+00:00", "Z"),
            "start_time": match_start.isoformat().replace("+00:00", "Z"),
            "status": 1,
            "extra_config": {"max_total_players": 40},
        },
    )
    assert ev.status_code == 200, ev.text
    assert ev.json()["title"] == "My Hosted Game"
    assert ev.json()["venue_name"] == "Riverside Pitch A"
    assert ev.json()["duration_minutes"] == 90
    assert ev.json()["organizer_id"] == reg.json()["user"]["id"]
    assert ev.json()["extra_config"] == {"max_total_players": 40}


def test_create_event_me_forbidden_for_player(client: TestClient) -> None:
    email = _unique_email()
    reg = client.post(
        "/auth/register",
        json={
            "name": "Player Only",
            "email": email,
            "password": "password12",
            "role": "player",
        },
    )
    assert reg.status_code == 200
    token = reg.json()["access_token"]
    reg_open = datetime(2026, 7, 1, 9, 0, 0, tzinfo=timezone.utc)
    reg_close = datetime(2026, 7, 1, 19, 0, 0, tzinfo=timezone.utc)
    match_start = datetime(2026, 7, 3, 10, 0, 0, tzinfo=timezone.utc)
    r = client.post(
        "/events/me",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "title": "X",
            "sport_type": "Soccer",
            "venue_name": "X",
            "lat": 0.0,
            "long": 0.0,
            "price": 1.0,
            "max_slots": 5,
            "registration_start": reg_open.isoformat().replace("+00:00", "Z"),
            "registration_end": reg_close.isoformat().replace("+00:00", "Z"),
            "start_time": match_start.isoformat().replace("+00:00", "Z"),
            "status": 0,
        },
    )
    assert r.status_code == 403


def test_player_books_team_event_with_squad_name(client: TestClient) -> None:
    org = client.post(
        "/auth/register",
        json={
            "name": "Org Book",
            "email": _unique_email(),
            "password": "password12",
            "role": "organizer",
        },
    )
    assert org.status_code == 200
    org_id = org.json()["user"]["id"]

    pl = client.post(
        "/auth/register",
        json={
            "name": "Player Book",
            "email": _unique_email(),
            "password": "password12",
            "role": "player",
        },
    )
    assert pl.status_code == 200
    player_token = pl.json()["access_token"]

    start = datetime(2026, 8, 1, 17, 0, 0, tzinfo=timezone.utc)
    ev = client.post(
        "/events/",
        json={
            "organizer_id": org_id,
            "title": "Youth Cup",
            "sport_type": "Soccer",
            "lat": 12.0,
            "long": 77.0,
            "price": 0.0,
            "max_slots": 8,
            "start_time": start.isoformat().replace("+00:00", "Z"),
            "status": 1,
            "age_group": "U15",
            "competition_format": "knockout",
            "registration_mode": "team",
        },
    )
    assert ev.status_code == 200, ev.text
    event_id = ev.json()["id"]
    assert ev.json()["age_group"] == "U15"
    assert ev.json()["registration_mode"] == "team"

    book = client.post(
        f"/events/{event_id}/bookings/me",
        headers={"Authorization": f"Bearer {player_token}"},
        json={"team_name": "Silchar FC"},
    )
    assert book.status_code == 200, book.text
    assert book.json()["team_name"] == "Silchar FC"
    assert book.json()["team_id"] == 1

    roster = client.get(f"/events/{event_id}/bookings")
    assert roster.status_code == 200
    assert len(roster.json()) == 1

    mine = client.get(
        "/me/bookings",
        headers={"Authorization": f"Bearer {player_token}"},
    )
    assert mine.status_code == 200, mine.text
    assert len(mine.json()) == 1
    row = mine.json()[0]
    assert row["booking_id"] == book.json()["booking_id"]
    assert row["event"]["id"] == event_id
    assert row["event"]["title"] == "Youth Cup"


def test_create_event_player_not_organizer(client: TestClient) -> None:
    email = _unique_email()
    reg = client.post(
        "/auth/register",
        json={
            "name": "P",
            "email": email,
            "password": "password12",
            "role": "player",
        },
    )
    player_id = reg.json()["user"]["id"]
    start = datetime(2026, 6, 15, 18, 0, 0, tzinfo=timezone.utc)
    r = client.post(
        "/events/",
        json={
            "organizer_id": player_id,
            "title": "Bad",
            "sport_type": "Soccer",
            "lat": 0.0,
            "long": 0.0,
            "price": 1.0,
            "max_slots": 5,
            "start_time": start.isoformat().replace("+00:00", "Z"),
            "status": 0,
        },
    )
    assert r.status_code == 400


def test_event_schedule_get_and_put(client: TestClient) -> None:
    org = client.post(
        "/auth/register",
        json={
            "name": "Org Sch",
            "email": _unique_email(),
            "password": "password12",
            "role": "organizer",
        },
    )
    assert org.status_code == 200
    org_token = org.json()["access_token"]

    p1 = client.post(
        "/auth/register",
        json={
            "name": "P1",
            "email": _unique_email(),
            "password": "password12",
            "role": "player",
        },
    )
    p2 = client.post(
        "/auth/register",
        json={
            "name": "P2",
            "email": _unique_email(),
            "password": "password12",
            "role": "player",
        },
    )
    t1 = p1.json()["access_token"]
    t2 = p2.json()["access_token"]

    reg_open = datetime(2026, 8, 1, 9, 0, 0, tzinfo=timezone.utc)
    reg_close = datetime(2026, 8, 10, 19, 0, 0, tzinfo=timezone.utc)
    match_start = datetime(2026, 8, 15, 10, 0, 0, tzinfo=timezone.utc)
    ev = client.post(
        "/events/me",
        headers={"Authorization": f"Bearer {org_token}"},
        json={
            "title": "Cup",
            "sport_type": "Soccer",
            "venue_name": "Stadium",
            "lat": 12.0,
            "long": 77.0,
            "price": 100.0,
            "max_slots": 16,
            "registration_start": reg_open.isoformat().replace("+00:00", "Z"),
            "registration_end": reg_close.isoformat().replace("+00:00", "Z"),
            "start_time": match_start.isoformat().replace("+00:00", "Z"),
            "status": 1,
            "registration_mode": "team",
        },
    )
    assert ev.status_code == 200, ev.text
    event_id = ev.json()["id"]

    sch_empty = client.get(f"/events/{event_id}/schedule")
    assert sch_empty.status_code == 200
    assert sch_empty.json()["matches"] == []

    b1 = client.post(
        f"/events/{event_id}/bookings/me",
        headers={"Authorization": f"Bearer {t1}"},
        json={"team_name": "Alpha FC"},
    )
    b2 = client.post(
        f"/events/{event_id}/bookings/me",
        headers={"Authorization": f"Bearer {t2}"},
        json={"team_name": "Beta FC"},
    )
    assert b1.status_code == 200
    assert b2.status_code == 200
    tid1 = b1.json()["team_id"]
    tid2 = b2.json()["team_id"]

    when = datetime(2026, 8, 12, 16, 30, 0, tzinfo=timezone.utc)
    put = client.put(
        f"/events/{event_id}/schedule",
        headers={"Authorization": f"Bearer {org_token}"},
        json={
            "matches": [
                {
                    "id": 1,
                    "round": "Semi-final",
                    "home_team_id": tid1,
                    "away_team_id": tid2,
                    "home_team_name": "Alpha FC",
                    "away_team_name": "Beta FC",
                    "scheduled_at": when.isoformat().replace("+00:00", "Z"),
                    "venue": "Pitch 1",
                    "notes": "Knockout",
                }
            ]
        },
    )
    assert put.status_code == 200, put.text
    assert len(put.json()["matches"]) == 1

    got = client.get(f"/events/{event_id}/schedule")
    assert got.status_code == 200
    m0 = got.json()["matches"][0]
    assert m0["home_team_name"] == "Alpha FC"
    assert m0["away_team_name"] == "Beta FC"
    assert m0["venue"] == "Pitch 1"

    bad = client.put(
        f"/events/{event_id}/schedule",
        headers={"Authorization": f"Bearer {t1}"},
        json={"matches": []},
    )
    assert bad.status_code == 403


def test_event_schedule_patch_and_delete_match(client: TestClient) -> None:
    org = client.post(
        "/auth/register",
        json={
            "name": "Org Patch",
            "email": _unique_email(),
            "password": "password12",
            "role": "organizer",
        },
    )
    assert org.status_code == 200
    org_token = org.json()["access_token"]

    p1 = client.post(
        "/auth/register",
        json={
            "name": "Pa",
            "email": _unique_email(),
            "password": "password12",
            "role": "player",
        },
    )
    p2 = client.post(
        "/auth/register",
        json={
            "name": "Pb",
            "email": _unique_email(),
            "password": "password12",
            "role": "player",
        },
    )
    t1 = p1.json()["access_token"]

    reg_open = datetime(2026, 9, 1, 9, 0, 0, tzinfo=timezone.utc)
    reg_close = datetime(2026, 9, 10, 19, 0, 0, tzinfo=timezone.utc)
    match_start = datetime(2026, 9, 15, 10, 0, 0, tzinfo=timezone.utc)
    ev = client.post(
        "/events/me",
        headers={"Authorization": f"Bearer {org_token}"},
        json={
            "title": "Patch Cup",
            "sport_type": "Soccer",
            "venue_name": "Stadium",
            "lat": 12.0,
            "long": 77.0,
            "price": 100.0,
            "max_slots": 16,
            "registration_start": reg_open.isoformat().replace("+00:00", "Z"),
            "registration_end": reg_close.isoformat().replace("+00:00", "Z"),
            "start_time": match_start.isoformat().replace("+00:00", "Z"),
            "status": 1,
            "registration_mode": "team",
            "competition_format": "league",
        },
    )
    assert ev.status_code == 200, ev.text
    event_id = ev.json()["id"]

    b1 = client.post(
        f"/events/{event_id}/bookings/me",
        headers={"Authorization": f"Bearer {t1}"},
        json={"team_name": "Gamma FC"},
    )
    p2_tok = p2.json()["access_token"]
    b2 = client.post(
        f"/events/{event_id}/bookings/me",
        headers={"Authorization": f"Bearer {p2_tok}"},
        json={"team_name": "Delta FC"},
    )
    assert b1.status_code == 200
    assert b2.status_code == 200
    tid1 = b1.json()["team_id"]
    tid2 = b2.json()["team_id"]

    when = datetime(2026, 9, 12, 16, 30, 0, tzinfo=timezone.utc)
    put = client.put(
        f"/events/{event_id}/schedule",
        headers={"Authorization": f"Bearer {org_token}"},
        json={
            "matches": [
                {
                    "id": 1,
                    "round": "R1",
                    "home_team_id": tid1,
                    "away_team_id": tid2,
                    "home_team_name": "Gamma FC",
                    "away_team_name": "Delta FC",
                    "scheduled_at": when.isoformat().replace("+00:00", "Z"),
                    "venue": "Pitch A",
                    "notes": "First",
                },
                {
                    "id": 2,
                    "round": "R1",
                    "home_team_id": tid2,
                    "away_team_id": tid1,
                    "home_team_name": "Delta FC",
                    "away_team_name": "Gamma FC",
                    "scheduled_at": when.isoformat().replace("+00:00", "Z"),
                    "venue": "Pitch B",
                    "notes": "Second",
                },
            ]
        },
    )
    assert put.status_code == 200, put.text

    patch = client.patch(
        f"/events/{event_id}/schedule/matches/1",
        headers={"Authorization": f"Bearer {org_token}"},
        json={
            "status": "finished",
            "home_score": 2,
            "away_score": 1,
            "notes": "Full time",
        },
    )
    assert patch.status_code == 200, patch.text
    matches = patch.json()["matches"]
    assert len(matches) == 2
    m1 = next(m for m in matches if m["id"] == 1)
    assert m1["status"] == "finished"
    assert m1["home_score"] == 2
    assert m1["away_score"] == 1
    assert m1["notes"] == "Full time"

    empty_patch = client.patch(
        f"/events/{event_id}/schedule/matches/1",
        headers={"Authorization": f"Bearer {org_token}"},
        json={},
    )
    assert empty_patch.status_code == 400

    delete = client.delete(
        f"/events/{event_id}/schedule/matches/2",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert delete.status_code == 200
    assert len(delete.json()["matches"]) == 1
    assert delete.json()["matches"][0]["id"] == 1

    missing = client.delete(
        f"/events/{event_id}/schedule/matches/99",
        headers={"Authorization": f"Bearer {org_token}"},
    )
    assert missing.status_code == 404


def test_knockout_schedule_rejects_duplicate_pair(client: TestClient) -> None:
    org = client.post(
        "/auth/register",
        json={
            "name": "Org KO Dup",
            "email": _unique_email(),
            "password": "password12",
            "role": "organizer",
        },
    )
    assert org.status_code == 200
    org_token = org.json()["access_token"]

    p1 = client.post(
        "/auth/register",
        json={
            "name": "K1",
            "email": _unique_email(),
            "password": "password12",
            "role": "player",
        },
    )
    p2 = client.post(
        "/auth/register",
        json={
            "name": "K2",
            "email": _unique_email(),
            "password": "password12",
            "role": "player",
        },
    )
    t1 = p1.json()["access_token"]
    t2 = p2.json()["access_token"]

    reg_open = datetime(2026, 10, 1, 9, 0, 0, tzinfo=timezone.utc)
    reg_close = datetime(2026, 10, 10, 19, 0, 0, tzinfo=timezone.utc)
    match_start = datetime(2026, 10, 15, 10, 0, 0, tzinfo=timezone.utc)
    ev = client.post(
        "/events/me",
        headers={"Authorization": f"Bearer {org_token}"},
        json={
            "title": "KO Dup",
            "sport_type": "Soccer",
            "venue_name": "Stadium",
            "lat": 12.0,
            "long": 77.0,
            "price": 100.0,
            "max_slots": 16,
            "registration_start": reg_open.isoformat().replace("+00:00", "Z"),
            "registration_end": reg_close.isoformat().replace("+00:00", "Z"),
            "start_time": match_start.isoformat().replace("+00:00", "Z"),
            "status": 1,
            "registration_mode": "team",
            "competition_format": "knockout",
        },
    )
    assert ev.status_code == 200, ev.text
    event_id = ev.json()["id"]

    b1 = client.post(
        f"/events/{event_id}/bookings/me",
        headers={"Authorization": f"Bearer {t1}"},
        json={"team_name": "A FC"},
    )
    b2 = client.post(
        f"/events/{event_id}/bookings/me",
        headers={"Authorization": f"Bearer {t2}"},
        json={"team_name": "B FC"},
    )
    assert b1.status_code == 200
    assert b2.status_code == 200
    tid1 = b1.json()["team_id"]
    tid2 = b2.json()["team_id"]

    when = datetime(2026, 10, 12, 16, 30, 0, tzinfo=timezone.utc)
    dup = client.put(
        f"/events/{event_id}/schedule",
        headers={"Authorization": f"Bearer {org_token}"},
        json={
            "matches": [
                {
                    "id": 1,
                    "home_team_id": tid1,
                    "away_team_id": tid2,
                    "home_team_name": "A FC",
                    "away_team_name": "B FC",
                    "scheduled_at": when.isoformat().replace("+00:00", "Z"),
                },
                {
                    "id": 2,
                    "home_team_id": tid2,
                    "away_team_id": tid1,
                    "home_team_name": "B FC",
                    "away_team_name": "A FC",
                    "scheduled_at": when.isoformat().replace("+00:00", "Z"),
                },
            ]
        },
    )
    assert dup.status_code == 400


def test_league_schedule_rejects_third_fixture_same_pair(client: TestClient) -> None:
    org = client.post(
        "/auth/register",
        json={
            "name": "Org L3",
            "email": _unique_email(),
            "password": "password12",
            "role": "organizer",
        },
    )
    assert org.status_code == 200
    org_token = org.json()["access_token"]

    p1 = client.post(
        "/auth/register",
        json={
            "name": "L1",
            "email": _unique_email(),
            "password": "password12",
            "role": "player",
        },
    )
    p2 = client.post(
        "/auth/register",
        json={
            "name": "L2",
            "email": _unique_email(),
            "password": "password12",
            "role": "player",
        },
    )
    t1 = p1.json()["access_token"]
    t2 = p2.json()["access_token"]

    reg_open = datetime(2026, 11, 1, 9, 0, 0, tzinfo=timezone.utc)
    reg_close = datetime(2026, 11, 10, 19, 0, 0, tzinfo=timezone.utc)
    match_start = datetime(2026, 11, 15, 10, 0, 0, tzinfo=timezone.utc)
    ev = client.post(
        "/events/me",
        headers={"Authorization": f"Bearer {org_token}"},
        json={
            "title": "League 3",
            "sport_type": "Soccer",
            "venue_name": "Stadium",
            "lat": 12.0,
            "long": 77.0,
            "price": 100.0,
            "max_slots": 16,
            "registration_start": reg_open.isoformat().replace("+00:00", "Z"),
            "registration_end": reg_close.isoformat().replace("+00:00", "Z"),
            "start_time": match_start.isoformat().replace("+00:00", "Z"),
            "status": 1,
            "registration_mode": "team",
            "competition_format": "league",
        },
    )
    assert ev.status_code == 200, ev.text
    event_id = ev.json()["id"]

    b1 = client.post(
        f"/events/{event_id}/bookings/me",
        headers={"Authorization": f"Bearer {t1}"},
        json={"team_name": "X FC"},
    )
    b2 = client.post(
        f"/events/{event_id}/bookings/me",
        headers={"Authorization": f"Bearer {t2}"},
        json={"team_name": "Y FC"},
    )
    assert b1.status_code == 200
    assert b2.status_code == 200
    tid1 = b1.json()["team_id"]
    tid2 = b2.json()["team_id"]

    w1 = datetime(2026, 11, 12, 10, 0, 0, tzinfo=timezone.utc)
    w2 = datetime(2026, 11, 12, 12, 0, 0, tzinfo=timezone.utc)
    w3 = datetime(2026, 11, 12, 14, 0, 0, tzinfo=timezone.utc)
    trip = client.put(
        f"/events/{event_id}/schedule",
        headers={"Authorization": f"Bearer {org_token}"},
        json={
            "matches": [
                {
                    "id": 1,
                    "home_team_id": tid1,
                    "away_team_id": tid2,
                    "home_team_name": "X FC",
                    "away_team_name": "Y FC",
                    "scheduled_at": w1.isoformat().replace("+00:00", "Z"),
                },
                {
                    "id": 2,
                    "home_team_id": tid2,
                    "away_team_id": tid1,
                    "home_team_name": "Y FC",
                    "away_team_name": "X FC",
                    "scheduled_at": w2.isoformat().replace("+00:00", "Z"),
                },
                {
                    "id": 3,
                    "home_team_id": tid1,
                    "away_team_id": tid2,
                    "home_team_name": "X FC",
                    "away_team_name": "Y FC",
                    "scheduled_at": w3.isoformat().replace("+00:00", "Z"),
                },
            ]
        },
    )
    assert trip.status_code == 400


def test_knockout_eliminated_squad_cannot_play_later_fixture(client: TestClient) -> None:
    org = client.post(
        "/auth/register",
        json={
            "name": "Org KO Elim",
            "email": _unique_email(),
            "password": "password12",
            "role": "organizer",
        },
    )
    assert org.status_code == 200
    org_token = org.json()["access_token"]

    players = []
    for i in range(3):
        r = client.post(
            "/auth/register",
            json={
                "name": f"E{i}",
                "email": _unique_email(),
                "password": "password12",
                "role": "player",
            },
        )
        assert r.status_code == 200
        players.append(r.json()["access_token"])

    reg_open = datetime(2026, 12, 1, 9, 0, 0, tzinfo=timezone.utc)
    reg_close = datetime(2026, 12, 10, 19, 0, 0, tzinfo=timezone.utc)
    match_start = datetime(2026, 12, 15, 10, 0, 0, tzinfo=timezone.utc)
    ev = client.post(
        "/events/me",
        headers={"Authorization": f"Bearer {org_token}"},
        json={
            "title": "KO Elim",
            "sport_type": "Soccer",
            "venue_name": "Stadium",
            "lat": 12.0,
            "long": 77.0,
            "price": 100.0,
            "max_slots": 16,
            "registration_start": reg_open.isoformat().replace("+00:00", "Z"),
            "registration_end": reg_close.isoformat().replace("+00:00", "Z"),
            "start_time": match_start.isoformat().replace("+00:00", "Z"),
            "status": 1,
            "registration_mode": "team",
            "competition_format": "knockout",
        },
    )
    assert ev.status_code == 200, ev.text
    event_id = ev.json()["id"]

    tids = []
    for tok, name in zip(players, ("S1", "S2", "S3"), strict=True):
        b = client.post(
            f"/events/{event_id}/bookings/me",
            headers={"Authorization": f"Bearer {tok}"},
            json={"team_name": name},
        )
        assert b.status_code == 200
        tids.append(b.json()["team_id"])

    t1, t2, t3 = tids
    early = datetime(2026, 12, 12, 10, 0, 0, tzinfo=timezone.utc)
    late = datetime(2026, 12, 12, 18, 0, 0, tzinfo=timezone.utc)

    bad = client.put(
        f"/events/{event_id}/schedule",
        headers={"Authorization": f"Bearer {org_token}"},
        json={
            "matches": [
                {
                    "id": 1,
                    "home_team_id": t2,
                    "away_team_id": t3,
                    "home_team_name": "S2",
                    "away_team_name": "S3",
                    "scheduled_at": early.isoformat().replace("+00:00", "Z"),
                    "status": "finished",
                    "home_score": 2,
                    "away_score": 0,
                },
                {
                    "id": 2,
                    "home_team_id": t3,
                    "away_team_id": t1,
                    "home_team_name": "S3",
                    "away_team_name": "S1",
                    "scheduled_at": late.isoformat().replace("+00:00", "Z"),
                },
            ]
        },
    )
    assert bad.status_code == 400
