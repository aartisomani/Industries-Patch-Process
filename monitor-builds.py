#!/usr/bin/env python3
"""
Build Monitor - Read patch-state.json and output thread info for Claude to process.

This script does NOT require a Slack token.
It works the same way as Friday's Slack posting — Claude reads the threads
via MCP Slack tools and posts to GUS chatter.

Usage:
    python3 monitor-builds.py --version 260.12 --status
    python3 monitor-builds.py --version 260.12 --pending
    python3 monitor-builds.py --version 260.12 --mark-done CME --workitem-id a07XX... --build-details '{...}'

Flow:
    1. You run: ./check-builds.sh 260.12
    2. Script prints pending threads for Claude to check
    3. Claude reads each thread via MCP Slack tool
    4. Claude parses build details (Vertical, Build Job, Namespace, Package Version, Install URL)
    5. Claude posts to GUS WI chatter tagging the tech writer
    6. Claude calls: python3 monitor-builds.py --version 260.12 --mark-done CME ...
"""

import json
import argparse
from pathlib import Path
from datetime import datetime

SCRIPT_DIR         = Path(__file__).parent
STATE_FILE         = SCRIPT_DIR / "patch-state.json"
TECH_WRITER_CONFIG = SCRIPT_DIR / "tech-writer-config.json"

def load_state() -> dict:
    if STATE_FILE.exists():
        with open(STATE_FILE) as f:
            return json.load(f)
    return {}

def save_state(state: dict):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)

def load_tech_writers() -> dict:
    with open(TECH_WRITER_CONFIG) as f:
        return json.load(f)["verticals"]

def show_status(version: str):
    """Print full state for a version."""
    state = load_state()
    vs = state.get(version)
    if not vs:
        print(f"No state found for version {version}")
        return
    print(json.dumps(vs, indent=2))

def show_pending(version: str):
    """
    Print pending threads with all info Claude needs to:
    1. Read the Slack thread
    2. Parse build details
    3. Post to GUS WI chatter
    """
    state        = load_state()
    tech_writers = load_tech_writers()
    vs           = state.get(version, {})
    threads      = vs.get("slack_threads", {})
    results      = vs.get("build_results", {})
    work_items   = vs.get("work_items", {})

    if not threads:
        print(f"⚠️  No Slack threads registered for version {version}")
        print(f"   Run Friday's weekly-patch.sh first, then:")
        print(f"   python3 save-thread.py --version {version} --vertical CME --channel <id> --thread-ts <ts>")
        return

    pending = {v: t for v, t in threads.items()
               if not results.get(v, {}).get("chatter_posted")}
    done    = [v for v in threads if results.get(v, {}).get("chatter_posted")]

    if done:
        print(f"✅ Already processed: {', '.join(done)}\n")

    if not pending:
        print("🎉 All verticals processed! Nothing pending.")
        return

    print("=" * 60)
    print(f"PENDING VERTICALS ({len(pending)}) — needs build check")
    print("=" * 60)

    for vertical, thread_info in pending.items():
        tw          = tech_writers.get(vertical, {})
        tw_name     = tw.get("tech_writer_name", "")
        tw_slack_id = tw.get("tech_writer_slack_id", "")
        tw_gus_id   = tw.get("tech_writer_id", "")
        wi          = work_items.get(vertical, {})

        print(f"\n[{vertical}]")
        print(f"  Slack channel    : {thread_info.get('channel_id')}")
        print(f"  Thread ts        : {thread_info.get('thread_ts')}")
        print(f"  GUS Work Item    : {wi.get('name', 'N/A')} ({wi.get('id', 'N/A')})")
        print(f"  Tech Writer      : {tw_name}")
        print(f"  TW Slack ID      : {tw_slack_id}  → mention as <@{tw_slack_id}>")
        print(f"  TW GUS ID        : {tw_gus_id}")

    print("\n" + "=" * 60)
    print("INSTRUCTIONS FOR CLAUDE:")
    print("=" * 60)
    print("For each pending vertical above:")
    print("  1. Read the Slack thread using channel + thread_ts")
    print("  2. Find the IREBuildNotifier message")
    print("  3. Extract: Vertical, Build Job, Namespace, Package Version, Install URL")
    print("  4. Post to GUS WI chatter tagging the tech writer")
    print("  5. Run: python3 monitor-builds.py --version <ver> --mark-done <VERTICAL>")
    print("          --workitem-id <id> --build-details '<json>'")
    print("=" * 60)

def mark_done(version: str, vertical: str, workitem_id: str, build_details_json: str):
    """Mark a vertical as processed after Claude has posted to GUS chatter."""
    state = load_state()
    vs    = state.setdefault(version, {})
    results = vs.setdefault("build_results", {})

    try:
        build_details = json.loads(build_details_json) if build_details_json else {}
    except Exception:
        build_details = {}

    results[vertical] = {
        "chatter_posted": True,
        "posted_at":      datetime.now().isoformat(),
        "workitem_id":    workitem_id,
        "build_details":  build_details
    }
    state[version] = vs
    save_state(state)
    print(f"✅ [{vertical}] marked as done in patch-state.json")

def register_thread(version: str, vertical: str, channel_id: str, thread_ts: str):
    """Register a Slack thread for a vertical."""
    state = load_state()
    vs    = state.setdefault(version, {})
    threads = vs.setdefault("slack_threads", {})
    threads[vertical] = {
        "channel_id":     channel_id,
        "thread_ts":      thread_ts,
        "registered_at":  datetime.now().isoformat()
    }
    state[version] = vs
    save_state(state)
    print(f"✅ [{vertical}] thread registered  channel={channel_id}  ts={thread_ts}")

def main():
    parser = argparse.ArgumentParser(
        description="Build monitor state manager — works with Claude MCP tools (no Slack token needed)"
    )
    parser.add_argument("--version", required=True, help="Patch version e.g. 260.12")

    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--status",  action="store_true", help="Show full state for this version")
    group.add_argument("--pending", action="store_true", help="Show pending verticals for Claude to process")
    group.add_argument("--mark-done", metavar="VERTICAL",  help="Mark a vertical as done after chatter posted")
    group.add_argument("--add-thread", nargs=3,
                       metavar=("VERTICAL", "CHANNEL_ID", "THREAD_TS"),
                       help="Manually register a Slack thread")

    parser.add_argument("--workitem-id",    default="", help="GUS work item ID (used with --mark-done)")
    parser.add_argument("--build-details",  default="{}", help="JSON build details (used with --mark-done)")

    args = parser.parse_args()

    if args.status:
        show_status(args.version)
    elif args.pending:
        show_pending(args.version)
    elif args.mark_done:
        mark_done(args.version, args.mark_done, args.workitem_id, args.build_details)
    elif args.add_thread:
        vertical, channel_id, thread_ts = args.add_thread
        register_thread(args.version, vertical, channel_id, thread_ts)

if __name__ == "__main__":
    main()
