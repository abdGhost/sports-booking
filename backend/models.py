"""SQLAlchemy models for the Sports Booking App."""

import enum
from datetime import datetime

from sqlalchemy import DateTime, Enum, Float, ForeignKey, Integer, JSON, String, Text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class UserRole(str, enum.Enum):
    ORGANIZER = "organizer"
    PLAYER = "player"


class EventStatus(int, enum.Enum):
    DRAFT = 0
    OPEN = 1
    FULL = 2
    LIVE = 3
    COMPLETED = 4


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    role: Mapped[UserRole] = mapped_column(
        Enum(UserRole, native_enum=False, length=20),
        nullable=False,
    )
    rating: Mapped[float] = mapped_column(Float, default=0.0)
    last_lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    last_long: Mapped[float | None] = mapped_column(Float, nullable=True)

    organized_events: Mapped[list["SportEvent"]] = relationship(
        "SportEvent", back_populates="organizer", foreign_keys="SportEvent.organizer_id"
    )
    bookings: Mapped[list["Booking"]] = relationship("Booking", back_populates="user")


class SportEvent(Base):
    __tablename__ = "sport_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    organizer_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    sport_type: Mapped[str] = mapped_column(String(100), nullable=False)
    venue_name: Mapped[str] = mapped_column(String(255), default="", nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    duration_minutes: Mapped[int] = mapped_column(Integer, default=90, nullable=False)
    skill_level: Mapped[str | None] = mapped_column(String(50), nullable=True)
    contact_phone: Mapped[str | None] = mapped_column(String(40), nullable=True)
    lat: Mapped[float] = mapped_column(Float, nullable=False)
    long: Mapped[float] = mapped_column(Float, nullable=False)
    price: Mapped[float] = mapped_column(Float, nullable=False)
    max_slots: Mapped[int] = mapped_column(Integer, nullable=False)
    booked_slots: Mapped[int] = mapped_column(Integer, default=0)
    start_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    #: When registration opens / closes (organizer create flow). Optional for legacy rows.
    registration_start: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    registration_end: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    status: Mapped[int] = mapped_column(Integer, default=EventStatus.DRAFT.value)
    #: e.g. U12, U15, Open, 35+
    age_group: Mapped[str] = mapped_column(String(50), default="Open", nullable=False)
    #: league | knockout | group_knockout (organizer-facing; bracket UX comes later)
    competition_format: Mapped[str] = mapped_column(String(40), default="knockout", nullable=False)
    #: team = register as squads; individual = single-player slots
    registration_mode: Mapped[str] = mapped_column(String(20), default="team", nullable=False)
    #: Organizer-defined local rules (tournament dates, overs, caps, etc.)
    extra_config: Mapped[dict | None] = mapped_column(JSON, nullable=True)

    organizer: Mapped["User"] = relationship(
        "User", back_populates="organized_events", foreign_keys=[organizer_id]
    )
    bookings: Mapped[list["Booking"]] = relationship("Booking", back_populates="event")


class Booking(Base):
    __tablename__ = "bookings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    event_id: Mapped[int] = mapped_column(ForeignKey("sport_events.id"), nullable=False, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    payment_status: Mapped[str] = mapped_column(String(50), default="pending")
    #: Stripe PaymentIntent id when paying by card (pending until webhook).
    stripe_payment_intent_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    team_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    #: Squad display name (shared by all members of the same team_id for this event).
    team_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    #: Meet / check-in address set by organizer during live match (per player or team).
    checkin_address: Mapped[str | None] = mapped_column(Text, nullable=True)

    event: Mapped["SportEvent"] = relationship("SportEvent", back_populates="bookings")
    user: Mapped["User"] = relationship("User", back_populates="bookings")
