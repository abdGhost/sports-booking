"""Seed the hosted API with realistic events (no admin token required).

Uses POST /auth/register or /auth/login, then POST /events/me for each blueprint.

Optional: if env ADMIN_RESET_TOKEN is set, calls POST /admin/seed instead (faster; includes full/live booked counts).

Usage (from repo root or backend/):
  python tools/seed_live_api.py
  python tools/seed_live_api.py --from-index 11 --count 9   # resume after a failure

Env:
  API_BASE   — default https://sports-booking-32gk.onrender.com
"""

from __future__ import annotations

import argparse
import json
import os
import random
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

# Allow `python tools/seed_live_api.py` from backend/
_BACKEND = Path(__file__).resolve().parent.parent
if str(_BACKEND) not in sys.path:
    sys.path.insert(0, str(_BACKEND))

from realistic_event_templates import REALISTIC_EVENT_BLUEPRINTS  # noqa: E402


def _post(base: str, path: str, body: dict | None, headers: dict[str, str] | None = None) -> tuple[int, dict]:
    url = f"{base.rstrip('/')}{path}"
    data = None if body is None else json.dumps(body).encode("utf-8")
    h = {"Content-Type": "application/json", "Accept": "application/json"}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, data=data, headers=h, method="POST" if body is not None else "GET")
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            detail = json.loads(raw)
        except json.JSONDecodeError:
            detail = {"detail": raw or str(e)}
        return e.code, detail


def _admin_seed(base: str, token: str) -> None:
    # Silchar area
    payload = {
        "center_lat": 24.8181824,
        "center_long": 92.8145838,
        "radius_km": 15.0,
       "events": 20,
        "realistic": True,
    }
    code, out = _post(
        base,
        "/admin/seed",
        payload,
        headers={"X-Admin-Token": token},
    )
    if code != 200:
        raise SystemExit(f"admin seed failed HTTP {code}: {out}")
    print("admin seed OK:", out)


def _ensure_organizer(base: str, email: str, password: str, name: str) -> str:
    code, out = _post(
        base,
        "/auth/login",
        {"email": email, "password": password},
    )
    if code == 200 and "access_token" in out:
        return str(out["access_token"])
    code, out = _post(
        base,
        "/auth/register",
        {"email": email, "password": password, "name": name, "role": "organizer"},
    )
    if code == 200 and "access_token" in out:
        return str(out["access_token"])
    raise SystemExit(f"organizer auth failed (login/register): HTTP {code} {out}")


def _create_events_organizer(
    base: str,
    bearer: str,
    *,
    start_index: int = 0,
    total: int = 20,
) -> int:
    now = datetime.now(timezone.utc)
    headers = {"Authorization": f"Bearer {bearer}"}
    center_lat, center_long = 24.8181824, 92.8145838
    radius_km = 15.0
    created = 0
    n_bp = len(REALISTIC_EVENT_BLUEPRINTS)

    for k in range(total):
        i = start_index + k
        bp = REALISTIC_EVENT_BLUEPRINTS[i % n_bp]
        dlat = (random.uniform(-1, 1) * radius_km) / 110.574
        dlon = (random.uniform(-1, 1) * radius_km) / (111.320 * max(0.2, abs(center_lat)))
        lat = float(max(-90, min(90, center_lat + dlat)))
        lon = float(max(-180, min(180, center_long + dlon)))

        title = str(bp["title"])
        if i // n_bp > 0:
            title = f"{title} · Part {i // n_bp + 1}"

        start_time = now + timedelta(
            days=2 + (i % 24),
            hours=10 + (i % 8),
            minutes=(i * 11) % 55,
        )
        reg_start = now - timedelta(hours=2)
        reg_end = start_time - timedelta(hours=1)
        if reg_end <= now:
            reg_end = now + timedelta(hours=6)

        hint = str(bp.get("status_hint", "open"))
        if hint == "full":
            status = 2
        elif hint == "live":
            status = 3
        else:
            status = 1

        sk = bp.get("skill_level")
        body = {
            "title": title,
            "sport_type": str(bp["sport_type"]),
            "venue_name": str(bp["venue_name"]),
            "description": str(bp["description"]),
            "duration_minutes": int(bp.get("duration_minutes", 90)),
            "skill_level": str(sk) if sk else "all",
            "contact_phone": (f"+91-3842-250{i % 10}0" if (i % 3 == 0) else None),
            "lat": lat,
            "long": lon,
            "price": float(bp["price"]),
            "max_slots": int(bp["max_slots"]),
            "registration_start": reg_start.isoformat(),
            "registration_end": reg_end.isoformat(),
            "start_time": start_time.isoformat(),
            "status": status,
            "age_group": str(bp.get("age_group", "Open")),
            "competition_format": str(bp["competition_format"]),
            "registration_mode": str(bp["registration_mode"]),
        }
        code, out = _post(base, "/events/me", body, headers=headers)
        if code != 200:
            raise SystemExit(f"create event failed HTTP {code}: {out}")
        created += 1
    return created


def main() -> None:
    parser = argparse.ArgumentParser(description="Seed hosted Sports Booking API")
    parser.add_argument("--from-index", type=int, default=0, help="Blueprint/event index offset (resume)")
    parser.add_argument("--count", type=int, default=20, help="Number of events to create")
    args = parser.parse_args()

    base = os.environ.get("API_BASE", "https://sports-booking-32gk.onrender.com").rstrip("/")
    admin = os.environ.get("ADMIN_RESET_TOKEN", "").strip()
    if admin:
        print("Using ADMIN_RESET_TOKEN → /admin/seed")
        _admin_seed(base, admin)
        return

    email = os.environ.get("SEED_ORG_EMAIL", "organizer@sportsbooking.app")
    password = os.environ.get("SEED_ORG_PASSWORD", "Pass@12345")
    name = os.environ.get("SEED_ORG_NAME", "Silchar Demo Organizer")

    print(
        f"Seeding via organizer API at {base} as {email!r} "
        f"(from_index={args.from_index}, count={args.count})"
    )
    token = _ensure_organizer(base, email, password, name)
    n = _create_events_organizer(base, token, start_index=args.from_index, total=args.count)
    print(f"Created {n} events via POST /events/me")


if __name__ == "__main__":
    main()
