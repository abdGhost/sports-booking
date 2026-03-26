"""Password hashing and JWT helpers."""

import os
from datetime import datetime, timedelta, timezone

import jwt
from passlib.context import CryptContext

# Avoid environment-specific bcrypt backend issues; PBKDF2 is stable and secure.
pwd_context = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")

# Render / .env typically set SECRET_KEY; JWT_SECRET still supported if set.
_raw_secret = (os.environ.get("JWT_SECRET") or os.environ.get("SECRET_KEY") or "").strip()
SECRET_KEY = _raw_secret if _raw_secret else "dev-only-change-in-production"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_DAYS = 7


def hash_password(plain: str) -> str:
    return pwd_context.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def create_access_token(*, user_id: int, role: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(days=ACCESS_TOKEN_EXPIRE_DAYS)
    payload = {"sub": str(user_id), "role": role, "exp": expire}
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def decode_access_token(token: str) -> dict:
    return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
