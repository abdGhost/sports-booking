"""FastAPI application for the Sports Booking App."""

import json
from typing import Annotated
import urllib.error
import urllib.parse
import urllib.request
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone

from fastapi import Depends, FastAPI, Header, HTTPException, Path, Query
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from auth_utils import create_access_token, decode_access_token, hash_password, verify_password
from database import SessionLocal, get_db, init_db
from haversine import haversine_km
from models import Booking, EventStatus, SportEvent, User, UserRole
from schemas import (
    BookingAddressUpdate,
    BookingCreatePlayer,
    BookingPlayerRead,
    EventCreate,
    EventCreateForOrganizer,
    EventNearby,
    EventOrganizerPatch,
    EventRead,
    EventSchedulePut,
    EventScheduleRead,
    EventUpdateStatus,
    LoginRequest,
    ScheduledMatchItem,
    ScheduledMatchPatch,
    MyBookingRead,
    RegisterRequest,
    TokenResponse,
    UserLocationUpdate,
    UserPublic,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    _seed_demo_users_if_empty()
    _seed_demo_events_if_empty()
    _backfill_missing_password_hashes()
    _seed_demo_knockout_schedule()
    _seed_weekend_football_league()
    _seed_sunset_football_7v7_squads()
    yield


def _backfill_missing_password_hashes() -> None:
    """Set demo passwords for legacy rows created before auth."""
    db = SessionLocal()
    try:
        demo = hash_password("demo123")
        users = db.scalars(select(User)).all()
        changed = False
        for u in users:
            if u.password_hash is None and u.email in (
                "organizer@example.com",
                "player@example.com",
                "player2@example.com",
                "player3@example.com",
                "player4@example.com",
                "player5@example.com",
                "player6@example.com",
                "player7@example.com",
                "player8@example.com",
                *(f"wfl{i}@example.com" for i in range(1, 11)),
                *(f"sf7v7_{i}@example.com" for i in range(1, 11)),
            ):
                u.password_hash = demo
                changed = True
        if changed:
            db.commit()
    finally:
        db.close()


app = FastAPI(title="Sports Booking API", version="1.0.0", lifespan=lifespan)

# Browsers reject Access-Control-Allow-Origin: * together with credentials.
# Flutter web may be http://localhost:PORT or http://127.0.0.1:PORT — allow both + LAN dev.
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1|192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+)(:\d+)?",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _seed_demo_users_if_empty() -> None:
    """Ensure at least one organizer and one player exist for local testing."""
    db = SessionLocal()
    try:
        first = db.scalars(select(User).limit(1)).first()
        if first is not None:
            return
        demo_pw = hash_password("demo123")
        db.add_all(
            [
                User(
                    name="Demo Organizer",
                    email="organizer@example.com",
                    password_hash=demo_pw,
                    role=UserRole.ORGANIZER,
                    rating=4.5,
                ),
                User(
                    name="Demo Player",
                    email="player@example.com",
                    password_hash=demo_pw,
                    role=UserRole.PLAYER,
                    rating=3.8,
                ),
            ]
        )
        db.commit()
    finally:
        db.close()


def _seed_demo_events_if_empty() -> None:
    """Ensure a minimum set of sample nearby events for local UI/testing."""
    db = SessionLocal()
    try:
        organizer = db.scalars(
            select(User).where(User.role == UserRole.ORGANIZER).limit(1)
        ).first()
        if organizer is None:
            return

        now = datetime.now(timezone.utc)
        # Around SF coordinates used in the app default location.
        demo_events = [
            ("Sunset Football 7v7", "Football", 37.7749, -122.4194, 18.0, 14, 4, 1, 2),
            ("Downtown Hoops Night", "Basketball", 37.7810, -122.4100, 12.0, 10, 6, 3, 1),
            ("Bay Tennis Doubles", "Tennis", 37.7680, -122.4300, 15.0, 8, 3, 5, 1),
            ("Beach Volleyball Mix", "Volleyball", 37.7600, -122.4470, 10.0, 12, 7, 8, 1),
            ("Golden Gate Baseball", "Baseball", 37.7695, -122.4862, 20.0, 18, 9, 10, 1),
            ("City Ice Hockey Scrim", "Hockey", 37.7842, -122.4012, 22.0, 16, 11, 13, 1),
            ("Morning Football Drills", "Football", 37.7815, -122.4330, 9.0, 20, 12, 15, 1),
            ("Evening Pro Court", "Basketball", 37.7920, -122.4220, 14.0, 10, 8, 20, 2),
            ("Mission Tennis Ladder", "Tennis", 37.7599, -122.4148, 11.0, 8, 4, 22, 1),
            ("Harbor Volleyball Open", "Volleyball", 37.8078, -122.4177, 13.0, 12, 5, 24, 1),
            ("Weekend Baseball Clinic", "Baseball", 37.7650, -122.4570, 17.0, 18, 10, 30, 1),
            ("Rink Rush Friday", "Hockey", 37.7857, -122.4066, 19.0, 14, 6, 32, 1),
        ]

        existing_count = len(db.scalars(select(SportEvent.id)).all())
        needed = max(0, len(demo_events) - existing_count)
        if needed == 0:
            return

        rows = [
            SportEvent(
                organizer_id=organizer.id,
                title=title,
                sport_type=sport,
                venue_name="Demo venue",
                description="Seeded sample event for local testing.",
                duration_minutes=90,
                skill_level="all",
                contact_phone=None,
                lat=lat,
                long=lng,
                price=price,
                max_slots=max_slots,
                booked_slots=booked,
                start_time=now + timedelta(hours=hours),
                status=status,
            )
            for title, sport, lat, lng, price, max_slots, booked, hours, status in demo_events[:needed]
        ]
        db.add_all(rows)
        db.commit()
    finally:
        db.close()


def _seed_demo_knockout_schedule() -> None:
    """Idempotent: one team tournament with squad bookings + published schedule (for UI testing)."""
    db = SessionLocal()
    try:
        org = db.scalars(
            select(User).where(User.email == "organizer@example.com")
        ).first()
        if org is None:
            return

        title = "Demo Knockout Cup (schedule test)"
        ev = db.scalars(select(SportEvent).where(SportEvent.title == title)).first()
        now = datetime.now(timezone.utc)
        reg_open = now - timedelta(days=1)
        reg_close = now + timedelta(days=30)
        match_start = now + timedelta(days=45)

        if ev is None:
            ev = SportEvent(
                organizer_id=org.id,
                title=title,
                sport_type="Football",
                venue_name="Demo Stadium Field A",
                description=(
                    "Seeded knockout tournament with a published fixture list. "
                    "Log in as organizer@example.com / demo123 to edit the schedule."
                ),
                duration_minutes=90,
                skill_level="all",
                contact_phone=None,
                lat=37.7749,
                long=-122.4194,
                price=100.0,
                max_slots=64,
                booked_slots=0,
                start_time=match_start,
                registration_start=reg_open,
                registration_end=reg_close,
                status=EventStatus.OPEN.value,
                age_group="Open",
                competition_format="knockout",
                registration_mode="team",
                extra_config=None,
            )
            db.add(ev)
            db.commit()
            db.refresh(ev)

        demo_pw = hash_password("demo123")
        #: Eight squads (player@ … player8@) so the schedule can show multiple QF fixtures.
        player_specs: list[tuple[str, str, str]] = [
            ("player@example.com", "Demo Player", "North Stars"),
            ("player2@example.com", "Riya Verma", "South United"),
            ("player3@example.com", "Arjun Mehta", "East FC"),
            ("player4@example.com", "Kavya Nair", "West Warriors"),
            ("player5@example.com", "Vikram Singh", "Central City FC"),
            ("player6@example.com", "Neha Kapoor", "Riverside Rangers"),
            ("player7@example.com", "Rohit Das", "Hilltop Hawks"),
            ("player8@example.com", "Ananya Iyer", "Coastal Comets"),
        ]
        players: list[User] = []
        for email, name, _ in player_specs:
            u = db.scalars(select(User).where(User.email == email)).first()
            if u is None:
                u = User(
                    name=name,
                    email=email,
                    password_hash=demo_pw,
                    role=UserRole.PLAYER,
                    rating=3.5,
                )
                db.add(u)
                db.commit()
                db.refresh(u)
            players.append(u)

        booked_user_ids = {
            b.user_id
            for b in db.scalars(select(Booking).where(Booking.event_id == ev.id)).all()
        }

        for pl, (_, _, team_name) in zip(players, player_specs):
            if pl.id in booked_user_ids:
                continue
            max_tid = db.scalar(
                select(func.max(Booking.team_id)).where(Booking.event_id == ev.id)
            )
            next_tid = (max_tid or 0) + 1
            db.add(
                Booking(
                    event_id=ev.id,
                    user_id=pl.id,
                    payment_status="pending",
                    team_id=next_tid,
                    team_name=team_name,
                )
            )
        db.commit()
        db.refresh(ev)

        #: Extra roster rows on existing squads (same team_id; password demo123) — multi-player testing.
        bench_specs: list[tuple[str, str, str]] = [
            ("bench1@example.com", "Alex Bench", "North Stars"),
            ("bench2@example.com", "Sam Porter", "North Stars"),
            ("bench3@example.com", "Lee Chen", "South United"),
        ]
        booked_user_ids = {
            b.user_id
            for b in db.scalars(select(Booking).where(Booking.event_id == ev.id)).all()
        }
        for email, name, squad_name in bench_specs:
            tid = db.scalar(
                select(Booking.team_id)
                .where(Booking.event_id == ev.id)
                .where(Booking.team_name == squad_name)
                .where(Booking.team_id.isnot(None))
                .limit(1)
            )
            if tid is None:
                continue
            u = db.scalars(select(User).where(User.email == email)).first()
            if u is None:
                u = User(
                    name=name,
                    email=email,
                    password_hash=demo_pw,
                    role=UserRole.PLAYER,
                    rating=3.5,
                )
                db.add(u)
                db.commit()
                db.refresh(u)
            if u.id in booked_user_ids:
                continue
            db.add(
                Booking(
                    event_id=ev.id,
                    user_id=u.id,
                    payment_status="paid",
                    team_id=tid,
                    team_name=squad_name,
                )
            )
            booked_user_ids.add(u.id)
        db.commit()
        db.refresh(ev)

        if ev.max_slots < 64:
            ev.max_slots = 64

        ev.booked_slots = int(
            db.scalar(
                select(func.count(Booking.id)).where(Booking.event_id == ev.id)
            )
            or 0
        )
        db.commit()
        db.refresh(ev)

        rows = db.execute(
            select(Booking.team_id, Booking.team_name)
            .where(Booking.event_id == ev.id)
            .where(Booking.team_id.isnot(None))
            .order_by(Booking.id)
        ).all()
        team_map: dict[int, str] = {}
        for tid, tname in rows:
            if tid is None or tid in team_map:
                continue
            team_map[tid] = (tname or "").strip() or f"Team {tid}"
        ids_sorted = sorted(team_map.keys())
        n_teams = len(ids_sorted)

        base = dict(ev.extra_config or {})
        demo_schedule_v = 4
        # Rebuild when version bumps, fixtures missing, or squad count changes (new seed teams).
        skip_schedule = (
            base.get("schedule_demo_version") == demo_schedule_v
            and isinstance(base.get("scheduled_matches"), list)
            and len(base["scheduled_matches"]) > 0
            and base.get("schedule_demo_team_count") == n_teams
        )
        if skip_schedule:
            return

        if n_teams < 2:
            return

        # Pair squads (1v2, 3v4, …). Odd team out has no seeded fixture.
        matches: list[dict] = []
        for i in range(0, len(ids_sorted) - 1, 2):
            ha, aw = ids_sorted[i], ids_sorted[i + 1]
            mid = len(matches) + 1
            kick = now + timedelta(days=5 + mid * 2)
            pitch = (mid - 1) % 4 + 1
            matches.append(
                {
                    "id": mid,
                    "round": "Quarter-final",
                    "home_team_id": ha,
                    "away_team_id": aw,
                    "home_team_name": team_map[ha],
                    "away_team_name": team_map[aw],
                    "scheduled_at": kick.isoformat().replace("+00:00", "Z"),
                    "venue": f"Pitch {pitch} — Demo Stadium",
                    "notes": f"Seeded demo QF — match {mid}",
                }
            )

        base["scheduled_matches"] = matches
        base["schedule_demo_version"] = demo_schedule_v
        base["schedule_demo_team_count"] = n_teams
        ev.extra_config = base
        db.commit()
    finally:
        db.close()


def _seed_weekend_football_league() -> None:
    """Idempotent: team-mode league with 10 booked squads (fixture / schedule testing)."""
    db = SessionLocal()
    try:
        org = db.scalars(
            select(User).where(User.email == "organizer@example.com")
        ).first()
        if org is None:
            return

        title = "Weekend Football League"
        ev = db.scalars(select(SportEvent).where(SportEvent.title == title)).first()
        now = datetime.now(timezone.utc)
        reg_open = now - timedelta(days=2)
        reg_close = now + timedelta(days=60)
        season_start = now + timedelta(days=14)

        if ev is None:
            ev = SportEvent(
                organizer_id=org.id,
                title=title,
                sport_type="Football",
                venue_name="Marina Community Pitch",
                description=(
                    "Seeded weekend league (10 squads). Log in as organizer@example.com / demo123. "
                    "Captains: wfl1@ … wfl10@example.com / demo123."
                ),
                duration_minutes=90,
                skill_level="all",
                contact_phone=None,
                lat=37.8050,
                long=-122.4320,
                price=45.0,
                max_slots=48,
                booked_slots=0,
                start_time=season_start,
                registration_start=reg_open,
                registration_end=reg_close,
                status=EventStatus.OPEN.value,
                age_group="Open",
                competition_format="league",
                registration_mode="team",
                extra_config=None,
            )
            db.add(ev)
            db.commit()
            db.refresh(ev)

        demo_pw = hash_password("demo123")
        #: One captain booking per squad — 10 teams total.
        squad_specs: list[tuple[str, str, str]] = [
            ("wfl1@example.com", "Chris A", "Riverside AFC"),
            ("wfl2@example.com", "Ben K", "Bay City FC"),
            ("wfl3@example.com", "Maya L", "Mission Strikers"),
            ("wfl4@example.com", "Jordan P", "Presidio United"),
            ("wfl5@example.com", "Taylor R", "SOMA Athletic"),
            ("wfl6@example.com", "Sam V", "Castro FC"),
            ("wfl7@example.com", "Riley N", "Noe Valley Vets"),
            ("wfl8@example.com", "Casey M", "Dogpatch Dynamo"),
            ("wfl9@example.com", "Quinn D", "Richmond Rovers"),
            ("wfl10@example.com", "Jamie F", "Excelsior Eleven"),
        ]
        captains: list[User] = []
        for email, name, _ in squad_specs:
            u = db.scalars(select(User).where(User.email == email)).first()
            if u is None:
                u = User(
                    name=name,
                    email=email,
                    password_hash=demo_pw,
                    role=UserRole.PLAYER,
                    rating=3.5,
                )
                db.add(u)
                db.commit()
                db.refresh(u)
            captains.append(u)

        booked_user_ids = {
            b.user_id
            for b in db.scalars(select(Booking).where(Booking.event_id == ev.id)).all()
        }

        for pl, (_, _, team_name) in zip(captains, squad_specs):
            if pl.id in booked_user_ids:
                continue
            max_tid = db.scalar(
                select(func.max(Booking.team_id)).where(Booking.event_id == ev.id)
            )
            next_tid = (max_tid or 0) + 1
            db.add(
                Booking(
                    event_id=ev.id,
                    user_id=pl.id,
                    payment_status="paid",
                    team_id=next_tid,
                    team_name=team_name,
                )
            )
        db.commit()
        db.refresh(ev)

        ev.booked_slots = int(
            db.scalar(
                select(func.count(Booking.id)).where(Booking.event_id == ev.id)
            )
            or 0
        )
        if ev.max_slots < 48:
            ev.max_slots = 48
        db.commit()
        db.refresh(ev)

        rows = db.execute(
            select(Booking.team_id, Booking.team_name)
            .where(Booking.event_id == ev.id)
            .where(Booking.team_id.isnot(None))
            .order_by(Booking.id)
        ).all()
        team_map: dict[int, str] = {}
        for tid, tname in rows:
            if tid is None or tid in team_map:
                continue
            team_map[tid] = (tname or "").strip() or f"Team {tid}"
        ids_sorted = sorted(team_map.keys())
        n_teams = len(ids_sorted)

        base = dict(ev.extra_config or {})
        wfl_sched_v = 1
        skip_schedule = (
            base.get("wfl_schedule_seed_version") == wfl_sched_v
            and isinstance(base.get("scheduled_matches"), list)
            and len(base["scheduled_matches"]) > 0
            and base.get("wfl_schedule_team_count") == n_teams
        )
        if skip_schedule or n_teams < 2:
            return

        matches: list[dict] = []
        for i in range(0, len(ids_sorted) - 1, 2):
            ha, aw = ids_sorted[i], ids_sorted[i + 1]
            mid = len(matches) + 1
            kick = now + timedelta(days=7 + mid)
            pitch = (mid - 1) % 3 + 1
            matches.append(
                {
                    "id": mid,
                    "round": "League — Matchday 1",
                    "home_team_id": ha,
                    "away_team_id": aw,
                    "home_team_name": team_map[ha],
                    "away_team_name": team_map[aw],
                    "scheduled_at": kick.isoformat().replace("+00:00", "Z"),
                    "venue": f"Field {pitch} — Marina Community Pitch",
                    "notes": f"Seeded WFL — MD1 match {mid}",
                }
            )

        base["scheduled_matches"] = matches
        base["wfl_schedule_seed_version"] = wfl_sched_v
        base["wfl_schedule_team_count"] = n_teams
        ev.extra_config = base
        db.commit()
    finally:
        db.close()


def _seed_sunset_football_7v7_squads() -> None:
    """Idempotent: real squad rows for the generic demo listing 'Sunset Football 7v7' (roster + matchup tests)."""
    db = SessionLocal()
    try:
        org = db.scalars(
            select(User).where(User.email == "organizer@example.com")
        ).first()
        if org is None:
            return

        title = "Sunset Football 7v7"
        ev = db.scalars(
            select(SportEvent).where(func.trim(SportEvent.title) == title.strip())
        ).first()
        now = datetime.now(timezone.utc)
        if ev is None:
            reg_open = now - timedelta(days=1)
            reg_close = now + timedelta(days=30)
            ev = SportEvent(
                organizer_id=org.id,
                title=title,
                sport_type="Football",
                venue_name="Demo venue",
                description=(
                    "Seeded 7v7 demo — squads for schedule editor tests. "
                    "Captains: sf7v7_1@ … sf7v7_10@example.com / demo123."
                ),
                duration_minutes=90,
                skill_level="all",
                contact_phone=None,
                lat=37.7749,
                long=-122.4194,
                price=18.0,
                max_slots=40,
                booked_slots=0,
                start_time=now + timedelta(hours=1),
                registration_start=reg_open,
                registration_end=reg_close,
                status=EventStatus.OPEN.value,
                age_group="Open",
                competition_format="knockout",
                registration_mode="team",
                extra_config=None,
            )
            db.add(ev)
            db.commit()
            db.refresh(ev)
        if ev.organizer_id != org.id:
            ev.organizer_id = org.id
        ev.registration_mode = "team"
        ev.competition_format = "knockout"
        if ev.registration_start is None:
            ev.registration_start = now - timedelta(days=1)
        if ev.registration_end is None:
            ev.registration_end = now + timedelta(days=30)
        if ev.max_slots < 40:
            ev.max_slots = 40

        demo_pw = hash_password("demo123")
        #: Ten squads so the schedule editor always has enough pairs for fixtures.
        squad_specs: list[tuple[str, str, str]] = [
            ("sf7v7_1@example.com", "Alex R", "Sunset Reds"),
            ("sf7v7_2@example.com", "Jordan M", "Ocean Blues"),
            ("sf7v7_3@example.com", "Sam T", "Fog FC"),
            ("sf7v7_4@example.com", "Casey L", "Bridge United"),
            ("sf7v7_5@example.com", "Riley K", "Park Rangers"),
            ("sf7v7_6@example.com", "Morgan P", "Marina Stars"),
            ("sf7v7_7@example.com", "Drew H", "Hilltop 7"),
            ("sf7v7_8@example.com", "Jamie V", "Valencia Vipers"),
            ("sf7v7_9@example.com", "Noah W", "Pacific FC"),
            ("sf7v7_10@example.com", "Sky S", "Embarcadero Eleven"),
        ]
        captains: list[User] = []
        for email, name, _ in squad_specs:
            u = db.scalars(select(User).where(User.email == email)).first()
            if u is None:
                u = User(
                    name=name,
                    email=email,
                    password_hash=demo_pw,
                    role=UserRole.PLAYER,
                    rating=3.5,
                )
                db.add(u)
                db.commit()
                db.refresh(u)
            captains.append(u)

        booked_user_ids = {
            b.user_id
            for b in db.scalars(select(Booking).where(Booking.event_id == ev.id)).all()
        }

        for pl, (_, _, team_name) in zip(captains, squad_specs):
            if pl.id in booked_user_ids:
                continue
            max_tid = db.scalar(
                select(func.max(Booking.team_id)).where(Booking.event_id == ev.id)
            )
            next_tid = (max_tid or 0) + 1
            db.add(
                Booking(
                    event_id=ev.id,
                    user_id=pl.id,
                    payment_status="paid",
                    team_id=next_tid,
                    team_name=team_name,
                )
            )
        db.commit()
        db.refresh(ev)

        ev.booked_slots = int(
            db.scalar(
                select(func.count(Booking.id)).where(Booking.event_id == ev.id)
            )
            or 0
        )
        db.commit()
        db.refresh(ev)

        rows = db.execute(
            select(Booking.team_id, Booking.team_name)
            .where(Booking.event_id == ev.id)
            .where(Booking.team_id.isnot(None))
            .order_by(Booking.id)
        ).all()
        team_map: dict[int, str] = {}
        for tid, tname in rows:
            if tid is None or tid in team_map:
                continue
            team_map[tid] = (tname or "").strip() or f"Team {tid}"
        ids_sorted = sorted(team_map.keys())
        n_teams = len(ids_sorted)

        base = dict(ev.extra_config or {})
        sunset_v = 2
        skip_schedule = (
            base.get("sunset_sf7_schedule_seed_version") == sunset_v
            and isinstance(base.get("scheduled_matches"), list)
            and len(base["scheduled_matches"]) > 0
            and base.get("sunset_sf7_team_count") == n_teams
        )
        if not skip_schedule and n_teams >= 2:
            matches: list[dict] = []
            for i in range(0, len(ids_sorted) - 1, 2):
                ha, aw = ids_sorted[i], ids_sorted[i + 1]
                mid = len(matches) + 1
                kick = now + timedelta(days=3 + mid * 2)
                pitch = (mid - 1) % 2 + 1
                matches.append(
                    {
                        "id": mid,
                        "round": "Quarter-final",
                        "home_team_id": ha,
                        "away_team_id": aw,
                        "home_team_name": team_map[ha],
                        "away_team_name": team_map[aw],
                        "scheduled_at": kick.isoformat().replace("+00:00", "Z"),
                        "venue": f"Synthetic pitch {pitch} — Demo venue",
                        "notes": f"Seeded Sunset 7v7 — QF {mid}",
                    }
                )
            base["scheduled_matches"] = matches
            base["sunset_sf7_schedule_seed_version"] = sunset_v
            base["sunset_sf7_team_count"] = n_teams
            ev.extra_config = base
            db.commit()
    finally:
        db.close()


def _nominatim_address_segments(address: dict) -> list[str]:
    """Build ordered address parts from Nominatim's structured `address` object."""
    segments: list[str] = []

    def add(val: object) -> None:
        if val is None:
            return
        t = str(val).strip()
        if not t or t in segments:
            return
        segments.append(t)

    road = (
        address.get("road")
        or address.get("pedestrian")
        or address.get("residential")
        or address.get("path")
        or address.get("footway")
        or address.get("cycleway")
    )
    hn = address.get("house_number")
    if road and hn:
        add(f"{hn} {road}".strip())
    elif road:
        add(road)
    elif hn:
        add(hn)
    if not segments:
        for key in ("house_name", "house", "building"):
            v = address.get(key)
            if v:
                add(v)
                break
    if not segments:
        for key in ("amenity", "shop", "tourism", "leisure", "man_made"):
            v = address.get(key)
            if v:
                add(v)
                break
    for key in (
        "neighbourhood",
        "quarter",
        "suburb",
        "city_district",
        "district",
        "borough",
    ):
        add(address.get(key))
    city = (
        address.get("city")
        or address.get("town")
        or address.get("village")
        or address.get("municipality")
        or address.get("hamlet")
    )
    add(city)
    add(address.get("county"))
    add(address.get("state_district"))
    add(address.get("state") or address.get("region"))
    add(address.get("postcode"))
    add(address.get("country"))
    return segments


def _nominatim_best_formatted(body: dict) -> str | None:
    """Use Nominatim's full display_name when present (complete hierarchy); else assemble from parts."""
    display = (body.get("display_name") or "").strip()
    if display:
        return display
    addr = body.get("address")
    if not isinstance(addr, dict):
        addr = {}
    line = ", ".join(_nominatim_address_segments(addr))
    return line or None


def _user_public(user: User, db: Session) -> UserPublic:
    """Build [UserPublic]; read coordinates with raw SQL (ORM can miss new SQLite columns)."""
    row = db.execute(
        text("SELECT last_lat, last_long FROM users WHERE id = :id"),
        {"id": user.id},
    ).one()
    return UserPublic(
        id=user.id,
        name=user.name,
        email=user.email,
        role=user.role.value,
        last_lat=row[0],
        last_long=row[1],
    )


def get_current_user(
    authorization: str | None = Header(None),
    db: Session = Depends(get_db),
) -> User:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Not authenticated")
    token = authorization.removeprefix("Bearer ").strip()
    try:
        payload = decode_access_token(token)
        user_id = int(payload["sub"])
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token") from None
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="User not found")
    return user


@app.post("/auth/register", response_model=TokenResponse)
def register(payload: RegisterRequest, db: Session = Depends(get_db)) -> TokenResponse:
    existing = db.scalars(select(User).where(User.email == str(payload.email))).first()
    if existing is not None:
        raise HTTPException(status_code=400, detail="Email already registered")
    role = UserRole.ORGANIZER if payload.role == "organizer" else UserRole.PLAYER
    user = User(
        name=payload.name,
        email=str(payload.email),
        password_hash=hash_password(payload.password),
        role=role,
        rating=0.0,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    token = create_access_token(user_id=user.id, role=user.role.value)
    return TokenResponse(access_token=token, user=_user_public(user, db))


@app.post("/auth/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> TokenResponse:
    user = db.scalars(select(User).where(User.email == str(payload.email))).first()
    if user is None or not user.password_hash:
        raise HTTPException(status_code=401, detail="Invalid email or password")
    if not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    token = create_access_token(user_id=user.id, role=user.role.value)
    return TokenResponse(access_token=token, user=_user_public(user, db))


@app.get("/auth/me", response_model=UserPublic)
def read_me(
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> UserPublic:
    return _user_public(current, db)


@app.patch("/auth/me/location", response_model=UserPublic)
def update_my_location(
    payload: UserLocationUpdate,
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> UserPublic:
    current.last_lat = payload.lat
    current.last_long = payload.long
    db.commit()
    return _user_public(current, db)


@app.get("/geocode/reverse")
def geocode_reverse(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
) -> dict[str, str]:
    """Reverse geocode via Nominatim — Flutter Web cannot use native geocoding."""
    params = urllib.parse.urlencode(
        {
            "lat": lat,
            "lon": lon,
            "format": "json",
            "zoom": 18,
            "addressdetails": 1,
            "namedetails": 1,
        }
    )
    url = f"https://nominatim.openstreetmap.org/reverse?{params}"
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "SportsBookingApp/1.0 (local dev; contact: n/a)",
            "Accept-Language": "en",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            body = json.loads(resp.read().decode())
    except (urllib.error.HTTPError, urllib.error.URLError, OSError, json.JSONDecodeError) as e:
        raise HTTPException(status_code=502, detail=f"Geocoding failed: {e}") from e
    formatted = _nominatim_best_formatted(body)
    display = body.get("display_name")
    if not formatted and not display:
        raise HTTPException(status_code=404, detail="No address for location")
    primary = formatted or str(display)
    out: dict[str, str] = {"formatted_address": primary}
    if display:
        out["display_name"] = str(display)
    return out


@app.post("/events/me", response_model=EventRead)
def create_my_event(
    payload: EventCreateForOrganizer,
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SportEvent:
    if current.role != UserRole.ORGANIZER:
        raise HTTPException(status_code=403, detail="Only organizers can create events")
    ev = SportEvent(
        organizer_id=current.id,
        title=payload.title,
        sport_type=payload.sport_type,
        venue_name=payload.venue_name,
        description=payload.description,
        duration_minutes=payload.duration_minutes,
        skill_level=payload.skill_level,
        contact_phone=payload.contact_phone,
        lat=payload.lat,
        long=payload.long,
        price=payload.price,
        max_slots=payload.max_slots,
        booked_slots=0,
        start_time=payload.start_time,
        registration_start=payload.registration_start,
        registration_end=payload.registration_end,
        status=payload.status,
        age_group=payload.age_group,
        competition_format=payload.competition_format,
        registration_mode=payload.registration_mode,
        extra_config=payload.extra_config,
    )
    db.add(ev)
    db.commit()
    db.refresh(ev)
    return ev


@app.post("/events/", response_model=EventRead)
def create_event(payload: EventCreate, db: Session = Depends(get_db)) -> SportEvent:
    organizer = db.get(User, payload.organizer_id)
    if organizer is None:
        raise HTTPException(status_code=404, detail="Organizer not found")
    if organizer.role != UserRole.ORGANIZER:
        raise HTTPException(status_code=400, detail="User is not an organizer")

    ev = SportEvent(
        organizer_id=payload.organizer_id,
        title=payload.title,
        sport_type=payload.sport_type,
        venue_name=payload.venue_name,
        description=payload.description,
        duration_minutes=payload.duration_minutes,
        skill_level=payload.skill_level,
        contact_phone=payload.contact_phone,
        lat=payload.lat,
        long=payload.long,
        price=payload.price,
        max_slots=payload.max_slots,
        booked_slots=0,
        start_time=payload.start_time,
        status=payload.status,
        age_group=payload.age_group,
        competition_format=payload.competition_format,
        registration_mode=payload.registration_mode,
        extra_config=payload.extra_config,
    )
    db.add(ev)
    db.commit()
    db.refresh(ev)
    return ev


@app.get("/events/nearby", response_model=list[EventNearby])
def events_nearby(
    lat: float = Query(..., description="Observer latitude"),
    long: float = Query(..., description="Observer longitude"),
    radius: float = Query(..., gt=0, description="Search radius in kilometers"),
    db: Session = Depends(get_db),
) -> list[EventNearby]:
    """Return events whose center lies within ``radius`` km (Haversine)."""
    events = db.scalars(select(SportEvent)).all()
    out: list[EventNearby] = []
    for ev in events:
        d = haversine_km(lat, long, ev.lat, ev.long)
        if d <= radius:
            out.append(
                EventNearby(
                    id=ev.id,
                    organizer_id=ev.organizer_id,
                    title=ev.title,
                    sport_type=ev.sport_type,
                    venue_name=ev.venue_name,
                    description=ev.description,
                    duration_minutes=ev.duration_minutes,
                    skill_level=ev.skill_level,
                    contact_phone=ev.contact_phone,
                    lat=ev.lat,
                    long=ev.long,
                    price=ev.price,
                    max_slots=ev.max_slots,
                    booked_slots=ev.booked_slots,
                    start_time=ev.start_time,
                    registration_start=ev.registration_start,
                    registration_end=ev.registration_end,
                    status=ev.status,
                    age_group=ev.age_group,
                    competition_format=ev.competition_format,
                    registration_mode=ev.registration_mode,
                    extra_config=ev.extra_config,
                    distance_km=round(d, 3),
                )
            )
    out.sort(key=lambda e: e.distance_km)
    return out


@app.get("/events/me", response_model=list[EventRead])
def list_my_events(
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[SportEvent]:
    """All events created by the authenticated organizer (upcoming / recent first)."""
    if current.role != UserRole.ORGANIZER:
        raise HTTPException(status_code=403, detail="Only organizers can list their events")
    stmt = (
        select(SportEvent)
        .where(SportEvent.organizer_id == current.id)
        .order_by(SportEvent.start_time.desc())
    )
    return list(db.scalars(stmt).all())


@app.get("/me/bookings", response_model=list[MyBookingRead])
def list_my_bookings(
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[MyBookingRead]:
    """All events the signed-in player has booked (newest match time first)."""
    if current.role != UserRole.PLAYER:
        raise HTTPException(status_code=403, detail="Only players can list their bookings")
    stmt = (
        select(Booking, SportEvent)
        .join(SportEvent, Booking.event_id == SportEvent.id)
        .where(Booking.user_id == current.id)
        .order_by(SportEvent.start_time.desc())
    )
    rows = db.execute(stmt).all()
    return [
        MyBookingRead(
            booking_id=b.id,
            payment_status=b.payment_status,
            team_id=b.team_id,
            team_name=b.team_name,
            address=b.checkin_address,
            event=EventRead.model_validate(ev),
        )
        for b, ev in rows
    ]


@app.get("/events/{event_id}", response_model=EventRead)
def get_event(event_id: int, db: Session = Depends(get_db)) -> SportEvent:
    ev = db.get(SportEvent, event_id)
    if ev is None:
        raise HTTPException(status_code=404, detail="Event not found")
    return ev


def _team_registry_for_event(db: Session, event_id: int) -> dict[int, str]:
    """First booking per team_id wins for display name."""
    rows = db.execute(
        select(Booking.team_id, Booking.team_name, Booking.id)
        .where(Booking.event_id == event_id)
        .where(Booking.team_id.isnot(None))
        .order_by(Booking.id)
    ).all()
    out: dict[int, str] = {}
    for tid, name, _ in rows:
        if tid is None or tid in out:
            continue
        out[tid] = (name or "").strip() or f"Team {tid}"
    return out


def _schedule_sort_key(m: ScheduledMatchItem) -> tuple:
    """Unscheduled fixtures sort last; then by kickoff; then by id."""
    ts = m.scheduled_at
    if ts is None:
        return (1, datetime.max.replace(tzinfo=timezone.utc), m.id)
    return (0, ts, m.id)


def _schedule_items_from_event(ev: SportEvent) -> list[ScheduledMatchItem]:
    """Parse and validate `extra_config.scheduled_matches`, ordered for display."""
    raw = (ev.extra_config or {}).get("scheduled_matches")
    if not raw or not isinstance(raw, list):
        return []
    matches: list[ScheduledMatchItem] = []
    for row in raw:
        if not isinstance(row, dict):
            continue
        try:
            matches.append(ScheduledMatchItem.model_validate(row))
        except Exception:
            continue
    return sorted(matches, key=_schedule_sort_key)


def _require_organizer_schedule_access(ev: SportEvent, current: User) -> None:
    if current.role != UserRole.ORGANIZER:
        raise HTTPException(status_code=403, detail="Only organizers can modify the schedule")
    if ev.organizer_id != current.id:
        raise HTTPException(status_code=403, detail="Only the event owner can edit the schedule")
    if (ev.registration_mode or "individual").strip().lower() != "team":
        raise HTTPException(status_code=400, detail="Schedule applies to team/squad events only")


def _validate_fixture_teams(m: ScheduledMatchItem, team_ids: set[int]) -> None:
    if m.home_team_id == m.away_team_id:
        raise HTTPException(status_code=400, detail="Home and away must be different teams")
    if m.home_team_id not in team_ids or m.away_team_id not in team_ids:
        raise HTTPException(
            status_code=400,
            detail="Each team id must match a registered squad for this event",
        )


@app.get("/events/{event_id}/schedule", response_model=EventScheduleRead)
def get_event_schedule(event_id: int, db: Session = Depends(get_db)) -> EventScheduleRead:
    """Public: squad vs squad fixtures set by the organizer (`extra_config.scheduled_matches`)."""
    ev = db.get(SportEvent, event_id)
    if ev is None:
        raise HTTPException(status_code=404, detail="Event not found")
    return EventScheduleRead(matches=_schedule_items_from_event(ev))


@app.put("/events/{event_id}/schedule", response_model=EventScheduleRead)
def put_event_schedule(
    event_id: int,
    payload: EventSchedulePut,
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> EventScheduleRead:
    """Owner-only: replace the full fixture list (team events only)."""
    ev = db.get(SportEvent, event_id)
    if ev is None:
        raise HTTPException(status_code=404, detail="Event not found")
    _require_organizer_schedule_access(ev, current)

    teams = _team_registry_for_event(db, event_id)
    team_ids = set(teams.keys())
    if not team_ids and payload.matches:
        raise HTTPException(
            status_code=400,
            detail="Register at least two squads before adding fixtures",
        )

    seen: set[int] = set()
    for m in payload.matches:
        if m.id in seen:
            raise HTTPException(status_code=400, detail=f"Duplicate match id {m.id}")
        seen.add(m.id)
        _validate_fixture_teams(m, team_ids)

    serialized = [m.model_dump(mode="json") for m in payload.matches]

    base = dict(ev.extra_config or {})
    base["scheduled_matches"] = serialized
    ev.extra_config = base
    db.commit()
    db.refresh(ev)
    return EventScheduleRead(matches=_schedule_items_from_event(ev))


@app.patch("/events/{event_id}/schedule/matches/{match_id}", response_model=EventScheduleRead)
def patch_event_schedule_match(
    event_id: int,
    match_id: Annotated[int, Path(ge=1)],
    payload: ScheduledMatchPatch,
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> EventScheduleRead:
    """Owner-only: merge fields into one fixture (e.g. score, status, kickoff)."""
    ev = db.get(SportEvent, event_id)
    if ev is None:
        raise HTTPException(status_code=404, detail="Event not found")
    _require_organizer_schedule_access(ev, current)

    patch_data = payload.model_dump(mode="json", exclude_unset=True)
    if not patch_data:
        raise HTTPException(status_code=400, detail="No fields to update")

    base = dict(ev.extra_config or {})
    raw_list = base.get("scheduled_matches")
    if not isinstance(raw_list, list):
        raw_list = []

    idx: int | None = None
    row_dict: dict | None = None
    for i, row in enumerate(raw_list):
        if isinstance(row, dict) and row.get("id") == match_id:
            idx = i
            row_dict = dict(row)
            break
    if idx is None or row_dict is None:
        raise HTTPException(status_code=404, detail="Match not found on this schedule")

    merged = {**row_dict, **patch_data}
    merged["id"] = match_id
    try:
        item = ScheduledMatchItem.model_validate(merged)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid fixture data: {e}") from e

    teams = _team_registry_for_event(db, event_id)
    team_ids = set(teams.keys())
    _validate_fixture_teams(item, team_ids)

    raw_list[idx] = item.model_dump(mode="json")
    base["scheduled_matches"] = raw_list
    ev.extra_config = base
    flag_modified(ev, "extra_config")
    db.commit()
    db.refresh(ev)
    return EventScheduleRead(matches=_schedule_items_from_event(ev))


@app.delete("/events/{event_id}/schedule/matches/{match_id}", response_model=EventScheduleRead)
def delete_event_schedule_match(
    event_id: int,
    match_id: Annotated[int, Path(ge=1)],
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> EventScheduleRead:
    """Owner-only: remove one fixture from the published schedule."""
    ev = db.get(SportEvent, event_id)
    if ev is None:
        raise HTTPException(status_code=404, detail="Event not found")
    _require_organizer_schedule_access(ev, current)

    base = dict(ev.extra_config or {})
    raw_list = base.get("scheduled_matches")
    if not isinstance(raw_list, list):
        raw_list = []

    before = len(raw_list)
    raw_list = [
        r
        for r in raw_list
        if not (isinstance(r, dict) and r.get("id") == match_id)
    ]
    if len(raw_list) == before:
        raise HTTPException(status_code=404, detail="Match not found on this schedule")

    base["scheduled_matches"] = raw_list
    ev.extra_config = base
    flag_modified(ev, "extra_config")
    db.commit()
    db.refresh(ev)
    return EventScheduleRead(matches=_schedule_items_from_event(ev))


@app.patch("/events/{event_id}", response_model=EventRead)
def update_event_status(
    event_id: int,
    payload: EventUpdateStatus,
    db: Session = Depends(get_db),
) -> SportEvent:
    ev = db.get(SportEvent, event_id)
    if ev is None:
        raise HTTPException(status_code=404, detail="Event not found")
    ev.status = payload.status
    db.commit()
    db.refresh(ev)
    return ev


@app.patch("/events/{event_id}/organizer", response_model=EventRead)
def patch_event_as_organizer(
    event_id: int,
    payload: EventOrganizerPatch,
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SportEvent:
    """Owner-only: update join fee, registration window, match start, extra_config (e.g. prizes)."""
    if current.role != UserRole.ORGANIZER:
        raise HTTPException(status_code=403, detail="Only organizers can update events")
    ev = db.get(SportEvent, event_id)
    if ev is None:
        raise HTTPException(status_code=404, detail="Event not found")
    if ev.organizer_id != current.id:
        raise HTTPException(status_code=403, detail="Only the event owner can edit this listing")

    if payload.price is not None:
        ev.price = payload.price
    if payload.registration_start is not None:
        ev.registration_start = payload.registration_start
    if payload.registration_end is not None:
        ev.registration_end = payload.registration_end
    if payload.start_time is not None:
        ev.start_time = payload.start_time

    rs = ev.registration_start
    re = ev.registration_end
    if rs is not None and re is not None and re <= rs:
        raise HTTPException(status_code=400, detail="registration_end must be after registration_start")
    if rs is not None and re is not None and ev.start_time <= re:
        raise HTTPException(status_code=400, detail="Match start_time must be after registration closes")

    if payload.extra_config is not None:
        base = dict(ev.extra_config or {})
        for k, v in payload.extra_config.items():
            if v is None:
                base.pop(k, None)
            else:
                base[k] = v
        ev.extra_config = base or None

    db.commit()
    db.refresh(ev)
    return ev


@app.get("/events/{event_id}/bookings", response_model=list[BookingPlayerRead])
def list_event_bookings(event_id: int, db: Session = Depends(get_db)) -> list[BookingPlayerRead]:
    ev = db.get(SportEvent, event_id)
    if ev is None:
        raise HTTPException(status_code=404, detail="Event not found")
    stmt = (
        select(Booking, User)
        .join(User, Booking.user_id == User.id)
        .where(Booking.event_id == event_id)
    )
    rows = db.execute(stmt).all()
    return [
        BookingPlayerRead(
            booking_id=b.id,
            user_id=u.id,
            name=u.name,
            email=u.email,
            payment_status=b.payment_status,
            team_id=b.team_id,
            team_name=b.team_name,
            address=b.checkin_address,
        )
        for b, u in rows
    ]


@app.post("/events/{event_id}/bookings/me", response_model=BookingPlayerRead)
def create_my_booking(
    event_id: int,
    payload: BookingCreatePlayer,
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> BookingPlayerRead:
    """Player books themselves; team events require a new squad name or join_team_id."""
    if current.role != UserRole.PLAYER:
        raise HTTPException(status_code=403, detail="Only players can book events")
    ev = db.get(SportEvent, event_id)
    if ev is None:
        raise HTTPException(status_code=404, detail="Event not found")
    if ev.status != EventStatus.OPEN.value:
        raise HTTPException(status_code=400, detail="Event is not open for booking")
    existing = db.scalars(
        select(Booking).where(
            Booking.event_id == event_id,
            Booking.user_id == current.id,
        )
    ).first()
    if existing is not None:
        raise HTTPException(status_code=400, detail="You already have a booking for this event")
    if ev.booked_slots >= ev.max_slots:
        raise HTTPException(status_code=400, detail="Event is full")

    reg = (ev.registration_mode or "team").strip().lower()
    team_id: int | None = None
    team_name: str | None = None

    if reg == "team":
        if payload.join_team_id is not None:
            ref = db.scalars(
                select(Booking).where(
                    Booking.event_id == event_id,
                    Booking.team_id == payload.join_team_id,
                )
            ).first()
            if ref is None:
                raise HTTPException(
                    status_code=404,
                    detail="No squad with that ID is registered for this event",
                )
            team_id = ref.team_id
            team_name = (ref.team_name or "").strip() or (payload.team_name or "").strip() or None
        elif payload.team_name and payload.team_name.strip():
            team_name = payload.team_name.strip()
            max_tid = db.scalar(
                select(func.max(Booking.team_id)).where(Booking.event_id == event_id)
            )
            team_id = (max_tid or 0) + 1
        else:
            raise HTTPException(
                status_code=400,
                detail="Enter a squad name (new team) or join_team_id to join an existing squad",
            )
    else:
        team_id = None
        team_name = None

    b = Booking(
        event_id=event_id,
        user_id=current.id,
        payment_status="pending",
        team_id=team_id,
        team_name=team_name,
    )
    db.add(b)
    ev.booked_slots += 1
    if ev.booked_slots >= ev.max_slots:
        ev.status = EventStatus.FULL.value
    db.commit()
    db.refresh(b)
    u = current
    return BookingPlayerRead(
        booking_id=b.id,
        user_id=u.id,
        name=u.name,
        email=str(u.email),
        payment_status=b.payment_status,
        team_id=b.team_id,
        team_name=b.team_name,
        address=b.checkin_address,
    )


@app.patch(
    "/events/{event_id}/bookings/{booking_id}",
    response_model=BookingPlayerRead,
)
def update_booking_checkin_address(
    event_id: int,
    booking_id: int,
    payload: BookingAddressUpdate,
    current: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> BookingPlayerRead:
    """Organizer sets a meet / check-in address for a booking while the match is live."""
    ev = db.get(SportEvent, event_id)
    if ev is None:
        raise HTTPException(status_code=404, detail="Event not found")
    if ev.organizer_id != current.id:
        raise HTTPException(status_code=403, detail="Only the event organizer can update check-in addresses")
    if ev.status != EventStatus.LIVE.value:
        raise HTTPException(
            status_code=400,
            detail="Check-in addresses can only be edited while the match is live",
        )
    b = db.get(Booking, booking_id)
    if b is None or b.event_id != event_id:
        raise HTTPException(status_code=404, detail="Booking not found")
    b.checkin_address = (payload.address or "").strip() or None
    db.commit()
    db.refresh(b)
    u = db.get(User, b.user_id)
    if u is None:
        raise HTTPException(status_code=500, detail="User missing for booking")
    return BookingPlayerRead(
        booking_id=b.id,
        user_id=u.id,
        name=u.name,
        email=u.email,
        payment_status=b.payment_status,
        team_id=b.team_id,
        team_name=b.team_name,
        address=b.checkin_address,
    )


def _mock_db_session() -> Session:
    """Example mock session factory for tests (override ``get_db``)."""
    return SessionLocal()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
