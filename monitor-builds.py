#!/usr/bin/env python3
"""
Build Monitor - Auto-detect when builds complete and post to GUS work items.

Usage:
    python3 monitor-builds.py --version 260.12 --check
    python3 monitor-builds.py --version 260.12 --post-if-ready

How it works:
1. Reads thread_ts per vertical from patch-state.json (saved during Friday's run)
2. Polls each vertical's Slack thread for a message from IREBuildNotifier
3. Parses: Vertical, Build Job, Namespace, Package Version, Install URL
4. Posts parsed build details to the GUS WI chatter tagging the tech writer
5. Updates patch-state.json marking that vertical as processed
"""

import os
import sys
import json
import re
import argparse
import subprocess
from datetime import datetime
from pathlib import Path

# ── Config ────────────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).parent
STATE_FILE  = SCRIPT_DIR / "patch-state.json"
TECH_WRITER_CONFIG = SCRIPT_DIR / "tech-writer-config.json"
SLACK_TOKEN_ENV    = "SLACK_BOT_TOKEN"

VERTICALS = ["CME", "INS", "OS", "INS-FSC"]

# Map vertical names that may appear in Slack messages to our canonical names
VERTICAL_ALIAS = {
    "CME":     "CME",
    "TELCO":   "CME",   # IREBuildNotifier sometimes uses TELCO for CME
    "INS":     "INS",
    "OS":      "OS",
    "INS-FSC": "INS-FSC",
    "FSC":     "INS-FSC",
}

# ── State helpers ─────────────────────────────────────────────────────────────
def load_state() -> dict:
    if STATE_FILE.exists():
        with open(STATE_FILE) as f:
            return json.load(f)
    return {}

def save_state(state: dict):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)
    print(f"💾 State saved → {STATE_FILE}")

def load_tech_writers() -> dict:
    with open(TECH_WRITER_CONFIG) as f:
        return json.load(f)["verticals"]

# ── Slack helpers ─────────────────────────────────────────────────────────────
def get_slack_client():
    try:
        from slack_sdk import WebClient
        token = os.environ.get(SLACK_TOKEN_ENV)
        if not token:
            print(f"❌  Missing env var {SLACK_TOKEN_ENV}")
            print("    Export it with:  export SLACK_BOT_TOKEN=xoxb-...")
            sys.exit(1)
        return WebClient(token=token)
    except ImportError:
        print("❌  slack_sdk not installed. Run: pip3 install slack_sdk")
        sys.exit(1)

def fetch_thread_messages(client, channel_id: str, thread_ts: str) -> list:
    """Return all replies in a Slack thread."""
    try:
        result = client.conversations_replies(
            channel=channel_id,
            ts=thread_ts,
            limit=200
        )
        return result.get("messages", [])
    except Exception as e:
        print(f"   ⚠️  Could not fetch thread {thread_ts}: {e}")
        return []

# ── Build message parser ──────────────────────────────────────────────────────
def parse_build_message(text: str) -> dict | None:
    """
    Parse an IREBuildNotifier message.

    Expected format (from snap):
        Vertical: CME
        Build Job: https://...
        Namespace: vlocity_cmt
        Package Version: 900.639
        Install URL: /packaging/installPackage.apexp?p0=04tg80000005q1BAAQ
    """
    if not text:
        return None

    # Must contain at least Package Version or Install URL to be a build message
    if "Install URL" not in text and "Package Version" not in text:
        return None

    def extract(pattern, txt, flags=0):
        m = re.search(pattern, txt, flags)
        return m.group(1).strip() if m else None

    vertical_raw = extract(r"Vertical[:\s]+([^\n]+)", text)
    build_job    = extract(r"Build Job[:\s]+(https?://[^\s\n]+)", text)
    namespace    = extract(r"Namespace[:\s]+([^\n]+)", text)
    pkg_version  = extract(r"Package Version[:\s]+([^\n]+)", text)

    # Install URL may wrap across lines - grab everything after the label
    install_url_match = re.search(r"Install URL[:\s]+(.+?)(?:\n\s*\n|\Z)", text, re.DOTALL)
    install_url = install_url_match.group(1).strip().replace("\n", "").replace(" ", "") if install_url_match else None

    if not pkg_version or not install_url:
        return None

    # Normalize vertical name
    canonical = VERTICAL_ALIAS.get(vertical_raw.upper() if vertical_raw else "", vertical_raw)

    return {
        "vertical_raw":   vertical_raw,
        "vertical":       canonical,
        "build_job":      build_job,
        "namespace":      namespace,
        "package_version": pkg_version,
        "install_url":    install_url,
    }

def find_build_in_thread(messages: list) -> dict | None:
    """Scan thread messages for an IREBuildNotifier build notification."""
    for msg in messages:
        # Check sender name (bot_profile or username)
        sender = (
            msg.get("bot_profile", {}).get("name", "") or
            msg.get("username", "") or
            msg.get("user", "")
        )
        text = msg.get("text", "")

        is_build_bot = "IRE" in sender.upper() or "BUILD" in sender.upper() or "NOTIF" in sender.upper()
        has_install  = "Install URL" in text or "Package Version" in text

        if is_build_bot or has_install:
            parsed = parse_build_message(text)
            if parsed:
                return parsed

    return None

# ── GUS chatter poster ────────────────────────────────────────────────────────
def build_chatter_body(build: dict, tech_writer_name: str, tech_writer_id: str) -> str:
    """Format the chatter message body."""
    install_full = build["install_url"]
    # If install URL is relative, make it absolute
    if install_full.startswith("/"):
        install_full = f"https://login.salesforce.com{install_full}"

    return (
        f"Build details for {build['vertical']} patch:\n\n"
        f"Vertical: {build['vertical_raw']}\n"
        f"Build Job: {build['build_job'] or 'N/A'}\n"
        f"Namespace: {build['namespace'] or 'N/A'}\n"
        f"Package Version: {build['package_version']}\n"
        f"Install URL: {install_full}\n\n"
        f"@{tech_writer_name} - Please proceed with release notes."
    )

def get_workitem_id(version: str, vertical: str) -> str | None:
    """Query GUS for the patch work item ID for this vertical + version."""
    query = (
        f"SELECT Id, Name FROM ADM_Work__c "
        f"WHERE Subject__c LIKE '%Patch {vertical} {version}%' "
        f"LIMIT 1"
    )
    result = subprocess.run(
        ["sf", "data", "query", "--target-org", "gus", "--query", query, "--json"],
        capture_output=True, text=True
    )
    try:
        data = json.loads(result.stdout)
        records = data.get("result", {}).get("records", [])
        if records:
            return records[0]["Id"], records[0]["Name"]
    except Exception:
        pass
    return None, None

def post_chatter(workitem_id: str, body: str, tech_writer_id: str) -> bool:
    """Post a Chatter FeedItem on a GUS work item mentioning the tech writer."""
    # Use Salesforce REST API via sf CLI to create FeedItem with mention
    chatter_payload = {
        "body": {
            "messageSegments": [
                {"type": "mention", "id": tech_writer_id},
                {"type": "text",    "text": f" {body}"}
            ]
        }
    }

    # Write payload to temp file
    tmp_file = SCRIPT_DIR / ".chatter_payload_tmp.json"
    with open(tmp_file, "w") as f:
        json.dump(chatter_payload, f)

    try:
        # Post via sf data create record
        result = subprocess.run(
            [
                "sf", "data", "create", "record",
                "--target-org", "gus",
                "--sobject", "FeedItem",
                "--values", f"ParentId='{workitem_id}' Body='{body}'",
                "--json"
            ],
            capture_output=True, text=True
        )
        data = json.loads(result.stdout)
        if data.get("status") == 0:
            return True
        else:
            print(f"   ⚠️  GUS error: {data.get('message', result.stderr)}")
            return False
    finally:
        if tmp_file.exists():
            tmp_file.unlink()

# ── Main workflow ─────────────────────────────────────────────────────────────
def check_and_process(version: str, dry_run: bool = False):
    state = load_state()
    tech_writers = load_tech_writers()
    client = get_slack_client()

    version_state = state.get(version, {})
    threads = version_state.get("slack_threads", {})

    if not threads:
        print(f"⚠️  No Slack threads found in state for version {version}")
        print(f"   Make sure Friday's weekly-patch.sh saved thread IDs to {STATE_FILE}")
        print(f"   Or add them manually with: python3 monitor-builds.py --version {version} --add-thread CME <thread_ts> <channel_id>")
        return

    print("=" * 60)
    print(f"BUILD MONITOR - Version {version}")
    print(f"Checking {len(threads)} vertical thread(s)...")
    print("=" * 60)

    results = version_state.get("build_results", {})

    for vertical, thread_info in threads.items():
        if results.get(vertical, {}).get("chatter_posted"):
            print(f"\n[{vertical}] ⏩ Already processed - skipping")
            continue

        channel_id = thread_info.get("channel_id")
        thread_ts  = thread_info.get("thread_ts")

        print(f"\n[{vertical}] 🔍 Checking thread {thread_ts} in {channel_id}...")

        messages = fetch_thread_messages(client, channel_id, thread_ts)
        print(f"   Found {len(messages)} message(s) in thread")

        build = find_build_in_thread(messages)

        if not build:
            print(f"[{vertical}] ⏳ No build details yet - will check again later")
            continue

        print(f"[{vertical}] ✅ Build found!")
        print(f"   Vertical:        {build['vertical_raw']}")
        print(f"   Namespace:       {build['namespace']}")
        print(f"   Package Version: {build['package_version']}")
        print(f"   Install URL:     {build['install_url']}")
        print(f"   Build Job:       {build['build_job']}")

        # Get tech writer
        tw = tech_writers.get(vertical, {})
        tw_id   = tw.get("tech_writer_id")
        tw_name = tw.get("tech_writer_email", "Tech Writer").split("@")[0].replace(".", " ").title()

        # Get GUS work item
        wi_id, wi_name = get_workitem_id(version, vertical)

        if not wi_id:
            print(f"[{vertical}] ❌ Work item not found in GUS for '{vertical} {version}'")
            continue

        print(f"[{vertical}] 📋 Work item: {wi_name} ({wi_id})")

        chatter_body = build_chatter_body(build, tw_name, tw_id)

        if dry_run:
            print(f"\n[{vertical}] 🔎 DRY RUN - Chatter would post:")
            print("-" * 40)
            print(chatter_body)
            print("-" * 40)
        else:
            print(f"[{vertical}] 💬 Posting to GUS chatter @{tw_name}...")
            success = post_chatter(wi_id, chatter_body, tw_id)
            if success:
                print(f"[{vertical}] ✅ Chatter posted successfully!")
                if vertical not in results:
                    results[vertical] = {}
                results[vertical]["chatter_posted"] = True
                results[vertical]["posted_at"]      = datetime.now().isoformat()
                results[vertical]["build_details"]  = build
                results[vertical]["workitem_id"]    = wi_id
                results[vertical]["workitem_name"]  = wi_name
            else:
                print(f"[{vertical}] ❌ Failed to post chatter")

    # Save updated state
    if not dry_run:
        version_state["build_results"] = results
        state[version] = version_state
        save_state(state)

    # Summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    pending = []
    done    = []
    for v in threads:
        if results.get(v, {}).get("chatter_posted"):
            done.append(v)
        else:
            pending.append(v)

    if done:
        print(f"✅ Processed ({len(done)}): {', '.join(done)}")
    if pending:
        print(f"⏳ Pending   ({len(pending)}): {', '.join(pending)}")
    if not pending:
        print("\n🎉 All verticals processed! Build monitoring complete.")
    print("=" * 60)


def add_thread(version: str, vertical: str, thread_ts: str, channel_id: str):
    """Manually register a Slack thread for a vertical (useful for testing)."""
    state = load_state()
    version_state = state.setdefault(version, {})
    threads = version_state.setdefault("slack_threads", {})
    threads[vertical] = {"channel_id": channel_id, "thread_ts": thread_ts}
    state[version] = version_state
    save_state(state)
    print(f"✅ Registered thread for [{vertical}] version {version}")
    print(f"   channel_id: {channel_id}")
    print(f"   thread_ts:  {thread_ts}")


def show_state(version: str):
    """Print current state for a version."""
    state = load_state()
    vs = state.get(version)
    if not vs:
        print(f"No state found for version {version}")
        return
    print(json.dumps(vs, indent=2))


# ── CLI ───────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="Monitor Slack threads for build details and post to GUS work items"
    )
    parser.add_argument("--version",  required=True, help="Patch version e.g. 260.12")
    parser.add_argument("--check",    action="store_true", help="Check threads and post to GUS if builds found")
    parser.add_argument("--dry-run",  action="store_true", help="Parse builds but don't post to GUS")
    parser.add_argument("--status",   action="store_true", help="Show current state for this version")
    parser.add_argument("--add-thread", nargs=3,
                        metavar=("VERTICAL", "THREAD_TS", "CHANNEL_ID"),
                        help="Manually register a Slack thread (for testing)")
    args = parser.parse_args()

    if args.status:
        show_state(args.version)
    elif args.add_thread:
        vertical, thread_ts, channel_id = args.add_thread
        add_thread(args.version, vertical, thread_ts, channel_id)
    elif args.check or args.dry_run:
        check_and_process(args.version, dry_run=args.dry_run)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
