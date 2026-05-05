#!/usr/bin/env python3
"""
Save Slack thread timestamps to patch-state.json after Friday posting.

Usage (called after each Slack message is sent):
    python3 save-thread.py --version 260.12 --vertical CME --channel U098NUEJ6G4 --thread-ts 1234567890.123456

Or bulk-save from .slack-post-data.json + Slack API to fetch sent thread ts:
    python3 save-thread.py --version 260.12 --fetch-threads

The --fetch-threads mode reads channel_id from .slack-post-data.json,
looks for your most recently sent messages in each channel, and saves
the thread_ts automatically.
"""

import os
import sys
import json
import argparse
from pathlib import Path
from datetime import datetime, timedelta

SCRIPT_DIR   = Path(__file__).parent
STATE_FILE   = SCRIPT_DIR / "patch-state.json"
SLACK_DATA   = SCRIPT_DIR / ".slack-post-data.json"
SLACK_TOKEN_ENV = "SLACK_BOT_TOKEN"

def load_state() -> dict:
    if STATE_FILE.exists():
        with open(STATE_FILE) as f:
            return json.load(f)
    return {}

def save_state(state: dict):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)
    print(f"💾 State saved → {STATE_FILE}")

def register_thread(version: str, vertical: str, channel_id: str, thread_ts: str):
    state = load_state()
    vs = state.setdefault(version, {})
    threads = vs.setdefault("slack_threads", {})
    threads[vertical] = {
        "channel_id": channel_id,
        "thread_ts":  thread_ts,
        "registered_at": datetime.now().isoformat()
    }
    state[version] = vs
    save_state(state)
    print(f"✅ [{vertical}] thread registered  channel={channel_id}  ts={thread_ts}")

def fetch_and_save_threads(version: str):
    """
    Auto-detect thread_ts values by finding the most recent messages
    in the channels listed in .slack-post-data.json.
    """
    try:
        from slack_sdk import WebClient
    except ImportError:
        print("❌ slack_sdk not installed. Run: pip3 install slack_sdk")
        sys.exit(1)

    token = os.environ.get(SLACK_TOKEN_ENV)
    if not token:
        print(f"❌ Missing env var {SLACK_TOKEN_ENV}")
        sys.exit(1)

    if not SLACK_DATA.exists():
        print(f"❌ {SLACK_DATA} not found — run weekly-patch.sh first")
        sys.exit(1)

    with open(SLACK_DATA) as f:
        messages = json.load(f)

    client = WebClient(token=token)

    # Look back 1 hour for recently posted messages
    oldest = str((datetime.now() - timedelta(hours=1)).timestamp())

    for entry in messages:
        channel_id = entry.get("channel_id")
        vertical   = entry.get("vertical")
        work_number = entry.get("work_number", "")

        if not channel_id or not vertical:
            continue

        print(f"[{vertical}] 🔍 Looking for thread in {channel_id}...")
        try:
            result = client.conversations_history(
                channel=channel_id,
                oldest=oldest,
                limit=20
            )
            msgs = result.get("messages", [])

            # Find the message that matches this vertical's work item number
            matched_ts = None
            for msg in msgs:
                txt = msg.get("text", "")
                if work_number in txt or vertical in txt:
                    matched_ts = msg.get("ts")
                    break

            if matched_ts:
                register_thread(version, vertical, channel_id, matched_ts)
            else:
                print(f"[{vertical}] ⚠️  Could not auto-detect thread — use --manual flag")
        except Exception as e:
            print(f"[{vertical}] ⚠️  Slack error: {e}")

def main():
    parser = argparse.ArgumentParser(description="Save Slack thread info to patch-state.json")
    parser.add_argument("--version", required=True, help="Patch version e.g. 260.12")
    parser.add_argument("--vertical",   help="Vertical name e.g. CME")
    parser.add_argument("--channel",    help="Slack channel/DM ID")
    parser.add_argument("--thread-ts",  help="Slack thread timestamp")
    parser.add_argument("--fetch-threads", action="store_true",
                        help="Auto-fetch thread_ts from Slack API using .slack-post-data.json")
    args = parser.parse_args()

    if args.fetch_threads:
        fetch_and_save_threads(args.version)
    elif args.vertical and args.channel and args.thread_ts:
        register_thread(args.version, args.vertical, args.channel, args.thread_ts)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
