"""Pydantic schemas for API I/O."""

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field


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
    start_time: datetime
    status: int = Field(default=0, ge=0, le=4)
    age_group: str = Field(default="Open", max_length=50)
    competition_format: str = Field(default="knockout", max_length=40)
    registration_mode: str = Field(default="team", max_length=20)
    extra_config: dict[str, Any] | None = Field(default=None)


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
    status: int
    age_group: str
    competition_format: str
    registration_mode: str
    extra_config: dict[str, Any] | None = None


class EventNearby(EventRead):
    distance_km: float


class EventUpdateStatus(BaseModel):
    status: int = Field(..., ge=0, le=4)


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


class BookingCreatePlayer(BaseModel):
    """Book the current user onto an event (squad-based when registration_mode is team)."""

    team_name: str | None = Field(default=None, max_length=120)
    join_team_id: int | None = Field(default=None, ge=1)


class BookingAddressUpdate(BaseModel):
    address: str | None = Field(default=None, max_length=500)


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
