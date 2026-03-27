"""Pydantic schemas for API I/O."""

from datetime import datetime
from typing import Any, Literal, Self

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator, model_validator


class EventCreate(BaseModel):
    organizer_id: int = Field(..., description="User id of the organizer")
    title: str
    sport_type: str
    venue_name: str = Field(default="", max_length=255)
    description: str | None = Field(default=None, max_length=4000)
    duration_minutes: int = Field(default=90, ge=15, le=24 * 60)
    skill_level: str | None = Field(default=None, max_length=50)
    contact_phone: str | None = Field(default=None, max_length=40)
    lat: float
    long: float
    price: float = Field(..., ge=0)
    max_slots: int = Field(..., ge=1)
    start_time: datetime
    status: int = Field(default=0, ge=0, le=4)
    age_group: str = Field(default="Open", max_length=50)
    competition_format: str = Field(default="knockout", max_length=40)
    registration_mode: str = Field(default="team", max_length=20)
    extra_config: dict[str, Any] | None = Field(default=None)


class EventCreateForOrganizer(BaseModel):
    """Create an event as the authenticated organizer (no organizer_id in body)."""

    title: str
    sport_type: str
    venue_name: str = Field(..., min_length=1, max_length=255)
    description: str | None = Field(default=None, max_length=4000)
    duration_minutes: int = Field(default=90, ge=15, le=24 * 60)
    skill_level: str | None = Field(default="all", max_length=50)
    contact_phone: str | None = Field(default=None, max_length=40)
    lat: float
    long: float
    price: float = Field(..., ge=0)
    max_slots: int = Field(..., ge=1)
    registration_start: datetime
    registration_end: datetime
    #: When the match / session actually starts (distinct from registration window).
    start_time: datetime
    status: int = Field(default=0, ge=0, le=4)
    age_group: str = Field(default="Open", max_length=50)
    competition_format: str = Field(default="knockout", max_length=40)
    registration_mode: str = Field(default="team", max_length=20)
    extra_config: dict[str, Any] | None = Field(default=None)

    @model_validator(mode="after")
    def registration_and_match_times(self) -> Self:
        if self.registration_end <= self.registration_start:
            raise ValueError("registration_end must be after registration_start")
        if self.start_time <= self.registration_end:
            raise ValueError("start_time must be after registration_end")
        return self


class EventOrganizerPatch(BaseModel):
    """Partial update for the event owner (join fee, registration, match time, prizes in extra_config)."""

    price: float | None = Field(default=None, ge=0)
    registration_start: datetime | None = None
    registration_end: datetime | None = None
    start_time: datetime | None = None
    extra_config: dict[str, Any] | None = None


class EventRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    organizer_id: int
    title: str
    sport_type: str
    venue_name: str
    description: str | None
    duration_minutes: int
    skill_level: str | None
    contact_phone: str | None
    lat: float
    long: float
    price: float
    max_slots: int
    booked_slots: int
    start_time: datetime
    registration_start: datetime | None = None
    registration_end: datetime | None = None
    status: int
    age_group: str
    competition_format: str
    registration_mode: str
    extra_config: dict[str, Any] | None = None


class EventNearby(EventRead):
    distance_km: float


class EventUpdateStatus(BaseModel):
    status: int = Field(..., ge=0, le=4)


class TeamRosterMemberRead(BaseModel):
    """Name/email the captain entered for a teammate (stored on the event)."""

    name: str
    email: str | None = None
    is_captain: bool = False


class BookingPlayerRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    booking_id: int
    user_id: int
    name: str
    email: EmailStr
    payment_status: str
    team_id: int | None
    team_name: str | None = None
    address: str | None = None
    #: Full declared roster for this squad (captain + teammates), when the captain registered the team.
    team_roster: list[TeamRosterMemberRead] | None = None
    #: Present only on create when card + paid amount; use with Stripe Payment Sheet.
    payment_client_secret: str | None = None
    stripe_publishable_key: str | None = None


class MyBookingRead(BaseModel):
    """Current user's booking with full event details (player home / My bookings)."""

    booking_id: int
    payment_status: str
    team_id: int | None
    team_name: str | None = None
    address: str | None = None
    event: EventRead


class TeamMemberCreate(BaseModel):
    """Optional teammate row submitted by the captain (Start a team flow only)."""

    name: str = Field(..., min_length=1, max_length=120)
    email: EmailStr | None = None

    @field_validator("email", mode="before")
    @classmethod
    def empty_email_is_none(cls, v: Any) -> Any:
        if v is None or (isinstance(v, str) and not v.strip()):
            return None
        return v


class BookingCreatePlayer(BaseModel):
    """Book the current user onto an event (squad-based when registration_mode is team)."""

    team_name: str | None = Field(default=None, max_length=120)
    join_team_id: int | None = Field(default=None, ge=1)
    #: Captain declares other players (no login); only used when starting a new team, not when join_team_id is set.
    team_members: list[TeamMemberCreate] | None = Field(default=None, max_length=24)
    #: `free` completes immediately as paid (demo). `card` uses Stripe when price > 0.
    payment_method: Literal["free", "card"] = "free"


class BookingAddressUpdate(BaseModel):
    address: str | None = Field(default=None, max_length=500)


MatchStatus = Literal["scheduled", "live", "finished", "postponed", "cancelled"]


class ScheduledMatchItem(BaseModel):
    """One fixture (e.g. knockout round) stored under event.extra_config['scheduled_matches']."""

    id: int = Field(..., ge=1, description="Stable id for UI editing (unique within the event)")
    round: str | None = Field(default=None, max_length=80)
    home_team_id: int = Field(..., ge=1)
    away_team_id: int = Field(..., ge=1)
    home_team_name: str = Field(..., max_length=120)
    away_team_name: str = Field(..., max_length=120)
    scheduled_at: datetime | None = None
    venue: str | None = Field(default=None, max_length=255)
    notes: str | None = Field(default=None, max_length=500)
    status: MatchStatus | None = None
    home_score: int | None = Field(default=None, ge=0)
    away_score: int | None = Field(default=None, ge=0)


class EventScheduleRead(BaseModel):
    matches: list[ScheduledMatchItem]


class EventSchedulePut(BaseModel):
    matches: list[ScheduledMatchItem]


class ScheduledMatchPatch(BaseModel):
    """Partial update for a single fixture (merge into existing row)."""

    round: str | None = Field(default=None, max_length=80)
    home_team_id: int | None = Field(default=None, ge=1)
    away_team_id: int | None = Field(default=None, ge=1)
    home_team_name: str | None = Field(default=None, max_length=120)
    away_team_name: str | None = Field(default=None, max_length=120)
    scheduled_at: datetime | None = None
    venue: str | None = Field(default=None, max_length=255)
    notes: str | None = Field(default=None, max_length=500)
    status: MatchStatus | None = None
    home_score: int | None = Field(default=None, ge=0)
    away_score: int | None = Field(default=None, ge=0)


class RegisterRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)
    role: Literal["organizer", "player"]


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class UserPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    email: EmailStr
    role: str
    last_lat: float | None = None
    last_long: float | None = None


class UserLocationUpdate(BaseModel):
    lat: float
    long: float


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserPublic
