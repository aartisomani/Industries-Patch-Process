#!/usr/bin/env python3
"""
tracker-block.py — Generate the Vlocity Release Tracker row block for a version.

Pulls Epic / RM WI / Package WI / CAB candidates (with Cloud__c) from GUS and
prints rows matching the existing pattern in FY26 Release Tracking Sheet of
https://docs.google.com/spreadsheets/d/1h57__av4D-Rk_0U2zhPP-A-Ux75xcJ-Ln9Frb3COzmA
(gid=2117744889).

Usage:
  python3 tracker-block.py <VERSION>

Output:
  - TSV block printed to stdout (paste-ready into Google Sheets).
  - Also writes .tracker-block.tsv next to the script for reference.

The block follows the historical pattern (e.g. 260.14, 262.7 entries) — version
banner row at the top, CAB section, then per-vertical RM/Devops section. Only
fills what Friday's GUS state knows; "Package numbers" is left blank for
Thursday to fill after the build, "Child Record Added?" is set to "Yes" since
weekly-patch.sh's Step 4 (link-cab-children.sh) ensures children are linked.

If the version isn't in release-schedule.json, falls back to GUS Epic dates.
"""

import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

SCRIPT_DIR    = Path(__file__).resolve().parent
SCHEDULE_FILE = SCRIPT_DIR / "release-schedule.json"
OUT_FILE      = SCRIPT_DIR / ".tracker-block.tsv"

# Friendly Cloud labels per vertical fall back to "—" if CAB row missing.
DEFAULT_VERTICAL_LABEL = {
    "CME":     "Communications",
    "INS":     "Insurance",
    "OS":      "OmniStudio",
    "INS-FSC": "Insurance FSC",
}


def sf(query: str):
    """Run an SOQL query against GUS and return parsed JSON. Aborts on error."""
    res = subprocess.run(
        ["sf", "data", "query", "--target-org", "gus", "--query", query, "--json"],
        capture_output=True, text=True
    )
    raw = re.sub(r"[\x00-\x1f]+", " ", res.stdout)
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        print(f"❌ SOQL response was not JSON.\n   Query: {query}\n   stdout: {res.stdout[:500]}\n   stderr: {res.stderr[:500]}", file=sys.stderr)
        sys.exit(1)
    if data.get("status") != 0:
        print(f"❌ SOQL error: {data.get('message','?')[:300]}\n   Query: {query}", file=sys.stderr)
        sys.exit(1)
    return data["result"]


def fmt_mmdd(date_str):
    """Convert YYYY-MM-DD or MM/DD or MM/DD/YYYY → MM/DD. Returns '' if blank."""
    if not date_str:
        return ""
    s = str(date_str).strip()
    if not s or s.upper() == "N/A":
        return ""
    # Try common formats
    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y", "%m/%d"):
        try:
            return datetime.strptime(s, fmt).strftime("%m/%d")
        except ValueError:
            continue
    # If already mm/dd, just return the first two parts.
    parts = s.split("/")
    if len(parts) >= 2 and parts[0].isdigit() and parts[1].isdigit():
        return f"{int(parts[0]):02d}/{int(parts[1]):02d}"
    return s


def schedule_for(version):
    """Returns (last_merge, sign_off, release) MM/DD strings; '' if missing."""
    if not SCHEDULE_FILE.exists():
        return "", "", ""
    try:
        with open(SCHEDULE_FILE) as f:
            d = json.load(f)
    except Exception:
        return "", "", ""
    entry = d.get(version) or {}
    return (
        fmt_mmdd(entry.get("last_merge")),
        fmt_mmdd(entry.get("sign_off")),
        fmt_mmdd(entry.get("release")),
    )


def cab_filter(vertical):
    return {
        "CME":     "Industries.CME",
        "INS":     "Industries.INS",
        "OS":      "Industries.OS",
        "INS-FSC": "Industries.INS",  # special-cased in query
    }.get(vertical, "")


def fetch_cab_candidates(vertical, version):
    """Returns list of {Name, Cloud, Work, Build, Stage} dicts for the vertical."""
    if vertical == "INS-FSC":
        where = (
            f"Scheduled_Build_Ref__c LIKE '%{version}%' "
            f"AND Scheduled_Build_Ref__c LIKE '%Industries.INS%FSC%'"
        )
    else:
        flt = cab_filter(vertical)
        where = (
            f"Scheduled_Build_Ref__c LIKE '%{version}%' "
            f"AND Scheduled_Build_Ref__c LIKE '%{flt}%' "
            f"AND (NOT Scheduled_Build_Ref__c LIKE '%FSC%')"
        )
    q = (
        "SELECT Name, Cloud__c, Work__c, Scheduled_Build_Ref__c, Stage__c "
        "FROM CAB_Patch_Candidate__c "
        f"WHERE {where} "
        "AND Stage__c IN ('Awaiting Approval', 'Pending Release', 'Close') "
        "AND Work__c != null "
        "ORDER BY Name"
    )
    out = []
    for r in sf(q)["records"]:
        out.append({
            "Name":  r.get("Name", ""),
            "Cloud": r.get("Cloud__c") or DEFAULT_VERTICAL_LABEL.get(vertical, ""),
            "Work":  r.get("Work__c", ""),
            "Build": r.get("Scheduled_Build_Ref__c", f"Industries.{vertical} {version}"),
            "Stage": r.get("Stage__c", ""),
        })
    return out


def fetch_w_number(work_id):
    """Return W-XXXXXXXX for a Work Id, or '' if missing."""
    if not work_id:
        return ""
    q = f"SELECT Name FROM ADM_Work__c WHERE Id = '{work_id}' LIMIT 1"
    res = sf(q)
    if res.get("totalSize", 0) == 0:
        return ""
    return res["records"][0].get("Name", "")


def fetch_rm_and_pkg(vertical, version):
    """Return (rm_w_name, pkg_w_name) as W-numbers for the vertical/version."""
    rm_q = (
        "SELECT Name FROM ADM_Work__c "
        f"WHERE Subject__c LIKE '[Vlocity-{vertical}] Patch {vertical} {version} %' "
        "AND Status__c != 'Closed' "
        "ORDER BY CreatedDate DESC LIMIT 1"
    )
    pkg_q = (
        "SELECT Name FROM ADM_Work__c "
        f"WHERE Subject__c LIKE '[Vlocity-{vertical}] Package creation for version {vertical} {version}%' "
        "AND Status__c != 'Closed' "
        "ORDER BY CreatedDate DESC LIMIT 1"
    )
    rm_res = sf(rm_q)
    pk_res = sf(pkg_q)
    rm  = rm_res["records"][0]["Name"] if rm_res.get("totalSize") else ""
    pkg = pk_res["records"][0]["Name"] if pk_res.get("totalSize") else ""
    return rm, pkg


def csv_quote(field):
    """Quote a field for CSV when it contains comma or quote."""
    s = "" if field is None else str(field)
    if any(c in s for c in [",", '"', "\n"]):
        return '"' + s.replace('"', '""') + '"'
    return s


def build_block(version, last_merge, sign_off, release, verticals, cab_per_vertical, rmpkg_per_vertical):
    rows = []

    # ── Banner row ─────────────────────────────────────────────────────────
    schedule_str = f"Last merge : {last_merge}, Sign off: : {sign_off} Release : {release}"
    banner = ["", version, "Running", schedule_str]
    rows.append(banner)

    # ── CAB section header ────────────────────────────────────────────────
    rows.append(["", "PR Status", "Team", "CAB Request", "Patch Candidate", "Scheduled build"])

    # ── CAB rows: one per CAB candidate, grouped by vertical (preserves order) ─
    for v in verticals:
        for cab in cab_per_vertical.get(v, []):
            patch_w = fetch_w_number(cab["Work"])
            rows.append([
                "", "", cab["Cloud"], cab["Name"], patch_w, cab["Build"]
            ])

    # blank separator
    rows.append([])

    # ── RM / Package section header ───────────────────────────────────────
    rows.append(["", "", "RM ticket", "Devops Ticket", "Package numbers", "Child Record Added?"])

    # ── Per-vertical row ──────────────────────────────────────────────────
    for v in verticals:
        rm, pkg = rmpkg_per_vertical.get(v, ("", ""))
        rows.append(["", v, rm, pkg, "", "Yes" if rm else ""])

    # ── Trailing blanks (matches existing block spacing) ──────────────────
    rows.append([])
    rows.append([])

    return rows


def to_csv(rows):
    return "\n".join(",".join(csv_quote(c) for c in r) for r in rows)


def to_tsv(rows):
    # Tab-separated for direct paste into Sheets without delimiter dialog.
    return "\n".join("\t".join("" if c is None else str(c) for c in r) for r in rows)


def main():
    if len(sys.argv) < 2:
        print("Usage: tracker-block.py <VERSION>", file=sys.stderr)
        sys.exit(1)

    version = sys.argv[1]

    # Schedule
    last_merge, sign_off, release = schedule_for(version)
    if not (last_merge and sign_off and release):
        print(f"⚠️  Schedule incomplete for {version} (last_merge={last_merge!r} sign_off={sign_off!r} release={release!r}). "
              f"Continuing — fill the blanks in manually after pasting.", file=sys.stderr)

    # Discover which verticals exist for this version (from CAB candidates).
    verticals_in_order = []
    cab_per_vertical = {}
    rmpkg_per_vertical = {}

    for v in ["CME", "INS", "OS", "INS-FSC"]:
        cabs = fetch_cab_candidates(v, version)
        if not cabs:
            continue
        verticals_in_order.append(v)
        cab_per_vertical[v] = cabs
        rm, pkg = fetch_rm_and_pkg(v, version)
        rmpkg_per_vertical[v] = (rm, pkg)

    if not verticals_in_order:
        print(f"❌ No CAB candidates found in GUS for version {version}. Nothing to add.", file=sys.stderr)
        sys.exit(1)

    rows = build_block(
        version, last_merge, sign_off, release,
        verticals_in_order, cab_per_vertical, rmpkg_per_vertical,
    )

    tsv = to_tsv(rows)
    csv = to_csv(rows)

    OUT_FILE.write_text(tsv + "\n")

    # Pretty terminal preview
    print("=" * 72, file=sys.stderr)
    print(f" VLOCITY TRACKER BLOCK for {version}", file=sys.stderr)
    print(f" Verticals: {', '.join(verticals_in_order)}", file=sys.stderr)
    print(f" Wrote: {OUT_FILE}", file=sys.stderr)
    print("=" * 72, file=sys.stderr)
    print("", file=sys.stderr)

    # The actual paste-ready content goes to stdout.
    print(tsv)


if __name__ == "__main__":
    main()
