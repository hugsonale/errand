# Utility helpers

import re
import math
from datetime import datetime, timezone


def mask_phone(phone: str) -> str:
    """
    Masks middle digits of a phone number for privacy.
    +2348012345678 → +234801***5678
    """
    if len(phone) < 8:
        return phone
    return phone[:6] + "***" + phone[-4:]


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Returns distance in kilometres between two GPS coordinates.
    Used for nearby agent queries until PostGIS is added in Phase 4.
    """
    R = 6371  # Earth radius in km
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def normalize_nigerian_phone(phone: str) -> str:
    """Converts 08012345678 to +2348012345678."""
    phone = phone.strip().replace(" ", "")
    if phone.startswith("0") and len(phone) == 11:
        return "+234" + phone[1:]
    return phone
