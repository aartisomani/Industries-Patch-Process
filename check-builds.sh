#!/bin/bash
# ============================================================
# CHECK BUILDS - Thursday build monitoring
# Usage:
#   ./check-builds.sh 260.12           # Show pending + Claude handles the rest
#   ./check-builds.sh 260.12 --status  # Show full state
#
# No Slack token needed — Claude reads threads via MCP tools
# ============================================================

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <version> [--status]"
    echo "Example: $0 260.12"
    exit 1
fi

VERSION="$1"
MODE="${2:-}"
SCRIPT_DIR="$(dirname "$0")"

echo "========================================"
echo "BUILD MONITOR - Version $VERSION"
echo "========================================"
echo ""

if [ "$MODE" == "--status" ]; then
    python3 "$SCRIPT_DIR/monitor-builds.py" --version "$VERSION" --status
else
    python3 "$SCRIPT_DIR/monitor-builds.py" --version "$VERSION" --pending
fi
