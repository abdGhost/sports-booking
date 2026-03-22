"""FastAPI application for the Sports Booking App."""

import json
import urllib.error
import urllib.parse
import urllib.request
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

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
    EventRead,
    EventUpdateStatus,
    LoginRequest,
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
        start_time=payload.registration_end,
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


@app.get("/events/{event_id}", response_model=EventRead)
def get_event(event_id: int, db: Session = Depends(get_db)) -> SportEvent:
    ev = db.get(SportEvent, event_id)
    if ev is None:
        raise HTTPException(status_code=404, detail="Event not found")
    return ev


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
