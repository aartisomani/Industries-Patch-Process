#!/bin/bash
# ============================================================
# CHECK BUILDS - Thursday build monitoring wrapper
# Usage:
#   ./check-builds.sh 260.12              # Check and post to GUS
#   ./check-builds.sh 260.12 --dry-run   # Preview without posting
#   ./check-builds.sh 260.12 --status    # Show current state
#
# Before running, ensure SLACK_BOT_TOKEN is exported:
#   export SLACK_BOT_TOKEN=xoxb-...
# ============================================================

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <version> [--dry-run | --status]"
    echo "Example: $0 260.12"
    echo "Example: $0 260.12 --dry-run"
    echo "Example: $0 260.12 --status"
    exit 1
fi

VERSION="$1"
MODE="${2:-}"
SCRIPT_DIR="$(dirname "$0")"

# Check SLACK token
if [ -z "$SLACK_BOT_TOKEN" ]; then
    echo "❌ SLACK_BOT_TOKEN not set."
    echo "   Run: export SLACK_BOT_TOKEN=xoxb-your-token-here"
    exit 1
fi

echo "========================================"
echo "BUILD MONITOR - Version $VERSION"
echo "========================================"
echo ""

if [ "$MODE" == "--status" ]; then
    python3 "$SCRIPT_DIR/monitor-builds.py" --version "$VERSION" --status
elif [ "$MODE" == "--dry-run" ]; then
    echo "🔎 DRY RUN MODE - No GUS posts will be made"
    echo ""
    python3 "$SCRIPT_DIR/monitor-builds.py" --version "$VERSION" --dry-run
else
    python3 "$SCRIPT_DIR/monitor-builds.py" --version "$VERSION" --check
fi
