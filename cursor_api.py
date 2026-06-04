"""Cursor dashboard API client (unofficial)."""

from __future__ import annotations  # noqa: F401

import os
from pathlib import Path
from typing import Any

import requests

BASE = "https://cursor.com"
COOKIE_NAME = "WorkosCursorSessionToken"
PROJECT_DIR = Path(__file__).parent


def load_token() -> str:
    token = os.environ.get("CURSOR_SESSION_TOKEN", "").strip()
    if not token:
        env_file = PROJECT_DIR / ".env"
        if env_file.exists():
            for line in env_file.read_text().splitlines():
                line = line.strip()
                if line.startswith("CURSOR_SESSION_TOKEN="):
                    token = line.split("=", 1)[1].strip().strip('"').strip("'")
                    break
    if not token:
        raise ValueError(
            "Missing CURSOR_SESSION_TOKEN. Add it to .env in the project folder."
        )
    return token


def make_session(token: str) -> requests.Session:
    session = requests.Session()
    session.cookies.set(COOKIE_NAME, token, domain="cursor.com")
    session.headers["Origin"] = "https://cursor.com"
    return session


def fetch_usage_summary(session: requests.Session | None = None) -> dict[str, Any]:
    if session is None:
        session = make_session(load_token())
    resp = session.get(f"{BASE}/api/usage-summary", timeout=30)
    if resp.status_code == 401:
        raise PermissionError("not_authenticated")
    resp.raise_for_status()
    return resp.json()


def usage_percent(summary: dict[str, Any]) -> float | None:
    """Dashboard total usage (totalPercentUsed), matching Cursor's main metric."""
    if summary.get("isUnlimited"):
        return None
    plan = summary.get("individualUsage", {}).get("plan", {})
    if plan.get("totalPercentUsed") is not None:
        return min(100.0, float(plan["totalPercentUsed"]))
    used = plan.get("used")
    limit = plan.get("limit")
    if used is not None and limit and limit > 0:
        return min(100.0, (used / limit) * 100.0)
    return None
