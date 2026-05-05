#!/usr/bin/env python3
"""
Save Slack thread timestamps to patch-state.json after Friday posting.
No Slack token needed — thread_ts values are passed in directly.

Usage (called by Claude after each Slack message is posted via MCP):
    python3 save-thread.py --version 260.12 --vertical CME --channel U098NUEJ6G4 --thread-ts 1234567890.123456
    python3 save-thread.py --version 260.12 --vertical INS --channel U098NUEJ6G4 --thread-ts 1234567890.654321
    ...
"""

import json
import argparse
from pathlib import Path
from datetime import datetime

SCRIPT_DIR = Path(__file__).parent
STATE_FILE = SCRIPT_DIR / "patch-state.json"

def load_state() -> dict:
    if STATE_FILE.exists():
        with open(STATE_FILE) as f:
            return json.load(f)
    return {}

def save_state(state: dict):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)

def register_thread(version: str, vertical: str, channel_id: str, thread_ts: str):
    state   = load_state()
    vs      = state.setdefault(version, {})
    threads = vs.setdefault("slack_threads", {})
    threads[vertical] = {
        "channel_id":    channel_id,
        "thread_ts":     thread_ts,
        "registered_at": datetime.now().isoformat()
    }
    state[version] = vs
    save_state(state)
    print(f"✅ [{vertical}] thread saved  channel={channel_id}  ts={thread_ts}")

def main():
    parser = argparse.ArgumentParser(description="Save Slack thread info to patch-state.json")
    parser.add_argument("--version",   required=True)
    parser.add_argument("--vertical",  required=True)
    parser.add_argument("--channel",   required=True)
    parser.add_argument("--thread-ts", required=True)
    args = parser.parse_args()
    register_thread(args.version, args.vertical, args.channel, args.thread_ts)

if __name__ == "__main__":
    main()
