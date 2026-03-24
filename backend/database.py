"""Database setup and dependency-injectable session factory."""

import os

from collections.abc import Generator
from contextlib import contextmanager

from sqlalchemy import create_engine, text
from dotenv import load_dotenv
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from models import Base

load_dotenv()

# In-memory SQLite for local dev; swap URL for production PostgreSQL etc.
# Tests set DATABASE_URL=sqlite:///:memory: before importing `main`.
DATABASE_URL = os.environ.get("DATABASE_URL", "sqlite:///./sports_booking.db")

_engine_kwargs: dict = {"connect_args": {"check_same_thread": False}}
# In-memory SQLite needs a single pooled connection or each session sees an empty DB.
if "sqlite" in DATABASE_URL and ":memory:" in DATABASE_URL:
    _engine_kwargs["poolclass"] = StaticPool

engine = create_engine(DATABASE_URL, **_engine_kwargs)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def init_db() -> None:
    Base.metadata.create_all(bind=engine)
    _sqlite_add_password_hash_column()
    _sqlite_add_user_location_columns()
    _sqlite_add_sport_event_extra_columns()
    _sqlite_add_sport_event_football_columns()
    _sqlite_add_sport_event_extra_config_column()
    _sqlite_add_sport_event_registration_window_columns()
    _sqlite_add_booking_checkin_address_column()
    _sqlite_add_booking_team_name_column()
    _sqlite_add_booking_stripe_payment_intent_column()


def _sqlite_add_password_hash_column() -> None:
    """Add password_hash to existing SQLite DBs created before auth."""
    if not str(engine.url).startswith("sqlite"):
        return
    with engine.connect() as conn:
        rows = conn.execute(text("PRAGMA table_info(users)")).fetchall()
        col_names = {r[1] for r in rows}
        if "password_hash" not in col_names:
            conn.execute(text("ALTER TABLE users ADD COLUMN password_hash VARCHAR(255)"))
            conn.commit()


def _sqlite_add_user_location_columns() -> None:
    """Add last_lat / last_long for storing the user's last known position."""
    if not str(engine.url).startswith("sqlite"):
        return
    with engine.connect() as conn:
        rows = conn.execute(text("PRAGMA table_info(users)")).fetchall()
        col_names = {r[1] for r in rows}
        if "last_lat" not in col_names:
            conn.execute(text("ALTER TABLE users ADD COLUMN last_lat FLOAT"))
            conn.commit()
        if "last_long" not in col_names:
            conn.execute(text("ALTER TABLE users ADD COLUMN last_long FLOAT"))
            conn.commit()


def _sqlite_add_sport_event_extra_columns() -> None:
    """Venue, description, duration, skill, contact for richer listings."""
    if not str(engine.url).startswith("sqlite"):
        return
    with engine.connect() as conn:
        rows = conn.execute(text("PRAGMA table_info(sport_events)")).fetchall()
        col_names = {r[1] for r in rows}
        if "venue_name" not in col_names:
            conn.execute(
                text("ALTER TABLE sport_events ADD COLUMN venue_name VARCHAR(255) DEFAULT ''")
            )
            conn.commit()
        if "description" not in col_names:
            conn.execute(text("ALTER TABLE sport_events ADD COLUMN description TEXT"))
            conn.commit()
        if "duration_minutes" not in col_names:
            conn.execute(
                text("ALTER TABLE sport_events ADD COLUMN duration_minutes INTEGER DEFAULT 90")
            )
            conn.commit()
        if "skill_level" not in col_names:
            conn.execute(text("ALTER TABLE sport_events ADD COLUMN skill_level VARCHAR(50)"))
            conn.commit()
        if "contact_phone" not in col_names:
            conn.execute(text("ALTER TABLE sport_events ADD COLUMN contact_phone VARCHAR(40)"))
            conn.commit()


def _sqlite_add_sport_event_football_columns() -> None:
    """Age group, competition format, team vs individual registration."""
    if not str(engine.url).startswith("sqlite"):
        return
    with engine.connect() as conn:
        rows = conn.execute(text("PRAGMA table_info(sport_events)")).fetchall()
        col_names = {r[1] for r in rows}
        if "age_group" not in col_names:
            conn.execute(
                text("ALTER TABLE sport_events ADD COLUMN age_group VARCHAR(50) DEFAULT 'Open'")
            )
            conn.commit()
        if "competition_format" not in col_names:
            conn.execute(
                text(
                    "ALTER TABLE sport_events ADD COLUMN competition_format VARCHAR(40) DEFAULT 'knockout'"
                )
            )
            conn.commit()
        if "registration_mode" not in col_names:
            conn.execute(
                text(
                    "ALTER TABLE sport_events ADD COLUMN registration_mode VARCHAR(20) DEFAULT 'team'"
                )
            )
            conn.commit()


def _sqlite_add_sport_event_extra_config_column() -> None:
    """extra_config JSON blob for organizer local rules."""
    if not str(engine.url).startswith("sqlite"):
        return
    with engine.connect() as conn:
        rows = conn.execute(text("PRAGMA table_info(sport_events)")).fetchall()
        col_names = {r[1] for r in rows}
        if "extra_config" not in col_names:
            conn.execute(text("ALTER TABLE sport_events ADD COLUMN extra_config TEXT"))
            conn.commit()


def _sqlite_add_sport_event_registration_window_columns() -> None:
    """registration_start / registration_end for organizer-defined booking window."""
    if not str(engine.url).startswith("sqlite"):
        return
    with engine.connect() as conn:
        rows = conn.execute(text("PRAGMA table_info(sport_events)")).fetchall()
        col_names = {r[1] for r in rows}
        if "registration_start" not in col_names:
            conn.execute(text("ALTER TABLE sport_events ADD COLUMN registration_start DATETIME"))
            conn.commit()
        if "registration_end" not in col_names:
            conn.execute(text("ALTER TABLE sport_events ADD COLUMN registration_end DATETIME"))
            conn.commit()


def _sqlite_add_booking_team_name_column() -> None:
    """Squad name for football-style team entries."""
    if not str(engine.url).startswith("sqlite"):
        return
    with engine.connect() as conn:
        rows = conn.execute(text("PRAGMA table_info(bookings)")).fetchall()
        col_names = {r[1] for r in rows}
        if "team_name" not in col_names:
            conn.execute(text("ALTER TABLE bookings ADD COLUMN team_name VARCHAR(120)"))
            conn.commit()


def _sqlite_add_booking_stripe_payment_intent_column() -> None:
    """Stripe PaymentIntent id for card checkout."""
    if not str(engine.url).startswith("sqlite"):
        return
    with engine.connect() as conn:
        rows = conn.execute(text("PRAGMA table_info(bookings)")).fetchall()
        col_names = {r[1] for r in rows}
        if "stripe_payment_intent_id" not in col_names:
            conn.execute(
                text("ALTER TABLE bookings ADD COLUMN stripe_payment_intent_id VARCHAR(255)")
            )
            conn.commit()


def _sqlite_add_booking_checkin_address_column() -> None:
    """Per-booking meet address (organizer sets during live match)."""
    if not str(engine.url).startswith("sqlite"):
        return
    with engine.connect() as conn:
        rows = conn.execute(text("PRAGMA table_info(bookings)")).fetchall()
        col_names = {r[1] for r in rows}
        if "checkin_address" not in col_names:
            conn.execute(text("ALTER TABLE bookings ADD COLUMN checkin_address TEXT"))
            conn.commit()


def get_db() -> Generator[Session, None, None]:
    """FastAPI dependency: yields a real SQLAlchemy session (mock-friendly via override)."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@contextmanager
def session_scope() -> Generator[Session, None, None]:
    """Context manager for scripts/tests."""
    db = SessionLocal()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()
