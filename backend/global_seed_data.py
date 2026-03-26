"""Realistic listings spread worldwide — no demo/test wording in user-facing fields.

Used by POST /admin/seed_global and optional startup when the DB has zero events."""

from __future__ import annotations

import random
from typing import Any

# (display city, lat, lng)
_HUBS: list[tuple[str, float, float]] = [
    ("Brooklyn", 40.6782, -73.9442),
    ("Los Angeles", 34.0522, -118.2437),
    ("Chicago", 41.8781, -87.6298),
    ("Mexico City", 19.4326, -99.1332),
    ("Toronto", 43.6532, -79.3832),
    ("London", 51.5074, -0.1278),
    ("Berlin", 52.5200, 13.4050),
    ("Madrid", 40.4168, -3.7038),
    ("Dubai", 25.2048, 55.2708),
    ("Singapore", 1.3521, 103.8198),
    ("Tokyo", 35.6762, 139.6503),
    ("Mumbai", 19.0760, 72.8777),
    ("Silchar", 24.8182, 92.8146),
    ("Sydney", -33.8688, 151.2093),
    ("São Paulo", -23.5505, -46.6333),
    ("Lagos", 6.5244, 3.3792),
    ("Cape Town", -33.9249, 18.4241),
]

# Four listings per hub — titles/venues use {city}
_SLOTS: list[dict[str, Any]] = [
    {
        "title": "Evening five-a-side · {city}",
        "sport_type": "Soccer",
        "venue_tmpl": "Central pitch · {city}",
        "description": "Rolling subs; fair-play rules. Arrive ten minutes early for check-in.",
        "registration_mode": "team",
        "competition_format": "knockout",
        "duration_minutes": 90,
        "max_slots": 20,
        "skill_level": "all",
        "price": 189.0,
        "age_group": "Open",
        "status_hint": "open",
    },
    {
        "title": "Night league basketball · {city}",
        "sport_type": "Basketball",
        "venue_tmpl": "Indoor court complex · {city}",
        "description": "Three games guaranteed per team; score sheets at desk.",
        "registration_mode": "team",
        "competition_format": "league",
        "duration_minutes": 120,
        "max_slots": 16,
        "skill_level": "intermediate",
        "price": 225.0,
        "age_group": "Open",
        "status_hint": "open",
    },
    {
        "title": "Club doubles ladder · {city}",
        "sport_type": "Badminton",
        "venue_tmpl": "Sports hall · {city}",
        "description": "Feather shuttles; warm-up courts open thirty minutes before start.",
        "registration_mode": "individual",
        "competition_format": "league",
        "duration_minutes": 120,
        "max_slots": 24,
        "skill_level": "intermediate",
        "price": 165.0,
        "age_group": "Open",
        "status_hint": "full",
    },
    {
        "title": "Weekend cricket · {city}",
        "sport_type": "Cricket",
        "venue_tmpl": "Municipal oval · {city}",
        "description": "T20 format; umpires named on the sheet at the ground.",
        "registration_mode": "team",
        "competition_format": "knockout",
        "duration_minutes": 150,
        "max_slots": 14,
        "skill_level": "all",
        "price": 1299.0,
        "age_group": "Open",
        "status_hint": "live",
    },
]


def global_listing_blueprints(*, seed: int = 20260326) -> list[dict[str, Any]]:
    """Return one dict per event, ready for SportEvent creation (plus status_hint)."""
    rng = random.Random(seed)
    out: list[dict[str, Any]] = []
    for city, clat, clon in _HUBS:
        for slot in _SLOTS:
            jlat = clat + rng.uniform(-0.035, 0.035)
            jlon = clon + rng.uniform(-0.035, 0.035)
            jlat = float(max(-89.9, min(89.9, jlat)))
            jlon = float(max(-179.9, min(179.9, jlon)))
            row = {k: v for k, v in slot.items() if k != "venue_tmpl"}
            row["venue_name"] = str(slot["venue_tmpl"]).format(city=city)
            row["title"] = str(slot["title"]).format(city=city)
            row["lat"] = jlat
            row["lon"] = jlon
            out.append(row)
    return out


def global_catalog_event_count() -> int:
    return len(_HUBS) * len(_SLOTS)
