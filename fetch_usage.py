#!/usr/bin/env python3
"""Fetch Cursor usage from the web dashboard's unofficial API."""

from __future__ import annotations

import json
import sys

from cursor_api import fetch_usage_summary, load_token, make_session, usage_percent

BASE = "https://cursor.com"


def fetch_usage_events(session, page: int = 1, page_size: int = 10) -> dict:
    resp = session.post(
        f"{BASE}/api/dashboard/get-filtered-usage-events",
        json={"page": page, "pageSize": page_size},
        timeout=30,
    )
    if resp.status_code == 401:
        raise SystemExit("401 not_authenticated — token expired. Paste a fresh cookie into .env")
    resp.raise_for_status()
    return resp.json()


def print_summary(data: dict) -> None:
    plan = data.get("individualUsage", {}).get("plan", {})
    on_demand = data.get("individualUsage", {}).get("onDemand", {})
    pct = usage_percent(data)

    print("\n=== Usage summary ===")
    print(f"Plan:        {data.get('membershipType', '?')}")
    if pct is not None:
        print(f"Usage:       {pct:.0f}%")
    print(f"Billing:     {data.get('billingCycleStart', '?')} → {data.get('billingCycleEnd', '?')}")
    print(f"Plan used:   {plan.get('used', '?')} / {plan.get('limit', '?')}")

    if on_demand.get("enabled"):
        used = on_demand.get("used", 0)
        print(f"On-demand:   {used} (units vary by plan — check dashboard for $)")


def print_events(data: dict) -> None:
    total = data.get("totalUsageEventsCount", 0)
    events = data.get("usageEventsDisplay", [])

    print(f"\n=== Recent events ({len(events)} of {total}) ===")
    for event in events:
        model = event.get("model", "?")
        cost = event.get("usageBasedCosts") or f"${event.get('chargedCents', 0) / 100:.2f}"
        tokens = event.get("tokenUsage") or {}
        out = tokens.get("outputTokens", "?")
        print(f"  {event.get('timestamp', '?')}  {model:<40}  {cost}  ({out} out tokens)")


def main() -> None:
    try:
        token = load_token()
    except ValueError as e:
        print(e, file=sys.stderr)
        sys.exit(1)

    session = make_session(token)

    print("Fetching usage summary...")
    summary = fetch_usage_summary(session)
    print_summary(summary)

    print("\nFetching recent events...")
    events = fetch_usage_events(session, page=1, page_size=10)
    print_events(events)

    if "--json" in sys.argv:
        print("\n=== Raw JSON ===")
        print(json.dumps({"summary": summary, "events": events}, indent=2))


if __name__ == "__main__":
    main()
