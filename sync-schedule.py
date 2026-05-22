#!/usr/bin/env python3
"""
sync-schedule.py — Sync release-schedule.json from the Non Core Google Sheet.

Reads the live sheet via the local MCP proxy (no extra auth needed).
Called automatically by create-release.sh before every run.

Usage: python3 sync-schedule.py
"""

import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

SHEET_FILE_ID   = "1Lxgeuu7eS-FTtmk_G-uUJS5ViIvE3pov_2WyuxFPtYQ"
SHEET_NAME      = "Non Core"
SCHEDULE_FILE   = Path(__file__).parent / "release-schedule.json"
MCP_URL         = "http://127.0.0.1:29051/mcp/servers/google"
MCP_TOKEN_FILE  = Path(__file__).parent.parent.parent / ".aisuite/marketplaces/aisuite/plugins/google/.mcp.json"

# Column indices (0-based) in the CSV rows
COL_PATCH       = 0   # 262 Patch #
COL_FLIGHT      = 1   # Flight Status
COL_SCOPE_FREEZE= 6   # Scope Freeze (Release Freeze)  → start
COL_LAST_MERGE  = 7   # Last Merge Date 11:30 AM IST   → last_merge
COL_SIGN_OFF    = 8   # Tech Readiness Signoff 4:00 PM → sign_off
COL_RELEASE     = 9   # Offcore/Mobile/Heroku PROD     → release


def get_mcp_token():
    with open(MCP_TOKEN_FILE) as f:
        d = json.load(f)
    return d["mcpServers"]["google"]["headers"]["Authorization"].replace("Bearer ", "")


def fetch_sheet(token):
    payload = {
        "jsonrpc": "2.0",
        "method": "tools/call",
        "params": {
            "name": "docs_get",
            "arguments": {"file_id": SHEET_FILE_ID, "sheet_name": SHEET_NAME}
        },
        "id": 1
    }
    result = subprocess.run(
        ["curl", "-s", MCP_URL,
         "-H", f"Authorization: Bearer {token}",
         "-H", "Content-Type: application/json",
         "-d", json.dumps(payload)],
        capture_output=True, text=True
    )
    response = json.loads(result.stdout)
    if response.get("result", {}).get("isError"):
        raise RuntimeError(f"Sheet fetch failed: {response}")
    return response["result"]["content"][0]["text"]


def parse_date(date_str):
    """Convert MM/DD/YYYY → YYYY-MM-DD. Returns None if invalid/N/A."""
    date_str = date_str.strip()
    if not date_str or date_str.upper() == "N/A":
        return None
    for fmt in ("%m/%d/%Y", "%m/%d/%y"):
        try:
            return datetime.strptime(date_str, fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    return None


def parse_mmdd(date_str):
    """Convert MM/DD/YYYY → MM/DD for last_merge and sign_off display."""
    full = parse_date(date_str)
    if not full:
        return None
    parts = full.split("-")
    return f"{int(parts[1]):02d}/{int(parts[2]):02d}"


def parse_sheet(text):
    """Parse the raw CSV-like sheet text into a dict keyed by version.

    Handles two row formats:
    1. Normal:  262.6, BUG FIXES ONLY, ..., scope, last_merge, sign_off, release
    2. Monthly: 262.7, "PLANNED - CODE DEPLOYMENT      <- version line, NO dates
                PLANNED - FEATURE ENABLEMENT", ..., scope, last_merge, sign_off, release  <- continuation
    """
    lines = text.strip().splitlines()
    versions = {}
    pending_patch = None  # waiting for continuation line with dates

    for line in lines:
        cols = [col.strip().strip('"') for col in line.split(",")]

        patch = cols[0].strip()
        is_version_line = bool(re.match(r'^\d+\.\d+$', patch))

        if is_version_line:
            flight = cols[1].upper() if len(cols) > 1 else ""
            is_monthly = "PLANNED" in flight
            last_merge = parse_mmdd(cols[COL_LAST_MERGE]) if len(cols) > COL_LAST_MERGE else None

            if last_merge:
                # All dates on this line (normal BUG FIXES row)
                scope_freeze = parse_date(cols[COL_SCOPE_FREEZE]) if len(cols) > COL_SCOPE_FREEZE else None
                sign_off     = parse_mmdd(cols[COL_SIGN_OFF]) if len(cols) > COL_SIGN_OFF else None
                release      = parse_date(cols[COL_RELEASE]) if len(cols) > COL_RELEASE else None
                if not release:
                    release = parse_date(cols[COL_SIGN_OFF]) if len(cols) > COL_SIGN_OFF else None
                entry = {
                    "start":           scope_freeze or release,
                    "last_merge":      last_merge,
                    "sign_off":        sign_off or last_merge,
                    "release":         release,
                    "last_merge_time": "11:30 AM IST",
                    "sign_off_time":   "03:00 PM IST"
                }
                if is_monthly:
                    entry["monthly"] = True
                versions[patch] = entry
                pending_patch = None
            else:
                # Dates on next continuation line (PLANNED monthly row)
                pending_patch = patch

        elif pending_patch:
            # Continuation line — extract all MM/DD/YYYY values in order
            date_cols = [col.strip() for col in cols if re.match(r'\d{2}/\d{2}/\d{4}', col.strip())]
            if len(date_cols) >= 3:
                scope_freeze = parse_date(date_cols[0])
                last_merge   = parse_mmdd(date_cols[1])
                sign_off     = parse_mmdd(date_cols[2])
                release      = parse_date(date_cols[3]) if len(date_cols) > 3 else parse_date(date_cols[2])
                versions[pending_patch] = {
                    "start":           scope_freeze or release,
                    "last_merge":      last_merge,
                    "sign_off":        sign_off or last_merge,
                    "release":         release,
                    "last_merge_time": "11:30 AM IST",
                    "sign_off_time":   "03:00 PM IST",
                    "monthly":         True
                }
            pending_patch = None

    return versions


def load_schedule():
    if SCHEDULE_FILE.exists():
        with open(SCHEDULE_FILE) as f:
            return json.load(f)
    return {}


def save_schedule(schedule):
    with open(SCHEDULE_FILE, "w") as f:
        json.dump(schedule, f, indent=2)


def main():
    print("🔄 Syncing release schedule from Non Core sheet...")

    try:
        token = get_mcp_token()
        text  = fetch_sheet(token)
    except Exception as e:
        print(f"⚠️  Could not fetch sheet: {e}")
        print("   Continuing with existing release-schedule.json")
        sys.exit(0)  # Non-fatal — don't block the release run

    new_versions = parse_sheet(text)
    if not new_versions:
        print("⚠️  No versions parsed from sheet — skipping update")
        sys.exit(0)

    schedule = load_schedule()
    notes    = schedule.get("_notes", [])
    added, updated = [], []

    for version, entry in new_versions.items():
        existing = schedule.get(version)
        if not existing:
            schedule[version] = entry
            added.append(version)
        else:
            # Preserve existing fields like status/cancelled, only update dates
            changed = False
            for key in ("start", "last_merge", "sign_off", "release", "monthly"):
                new_val = entry.get(key)
                old_val = existing.get(key)
                if new_val is not None and new_val != old_val:
                    existing[key] = new_val
                    changed = True
            # Remove monthly flag if no longer PLANNED
            if "monthly" not in entry and "monthly" in existing:
                del existing["monthly"]
                changed = True
            if changed:
                updated.append(version)

    # Preserve _notes and update timestamp
    notes_updated = [n for n in notes if not n.startswith("Last updated:")]
    notes_updated.append(f"Last updated: {datetime.now().strftime('%Y-%m-%d')} (auto-synced from Non Core sheet)")
    schedule["_notes"] = notes_updated

    save_schedule(schedule)

    if added:
        print(f"  ✅ Added:   {', '.join(sorted(added))}")
    if updated:
        print(f"  🔄 Updated: {', '.join(sorted(updated))}")
    if not added and not updated:
        print("  ✅ Already up to date")

    print("✅ Release schedule synced")


if __name__ == "__main__":
    main()
