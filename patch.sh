#!/bin/bash
# ============================================================
# PATCH - Master command dispatcher for patch release automation
#
# Usage:
#   run weekly patch <version>       → Run Friday weekly patch workflow
#   run check builds <version>       → Run Thursday build monitoring
#   run check builds <version> --status   → Show build state
#
# Examples:
#   run weekly patch 260.12
#   run check builds 260.12
#   run check builds 260.12 --status
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Helpers ───────────────────────────────────────────────────
usage() {
    echo ""
    echo "Usage:"
    echo "  run weekly patch <version>              Friday: CAB check + create epics/WIs/Slack threads"
    echo "  run check builds <version>              Thursday: Check threads for build details → post to GUS"
    echo "  run check builds <version> --status     Show current build state for a version"
    echo ""
    echo "Examples:"
    echo "  run weekly patch 260.12"
    echo "  run check builds 260.12"
    echo "  run check builds 260.12 --status"
    echo ""
}

# ── Arg parsing ───────────────────────────────────────────────
COMMAND="$1"
SUBCOMMAND="$2"
ARG1="$3"
ARG2="$4"

# ── Dispatch ──────────────────────────────────────────────────
case "$COMMAND $SUBCOMMAND" in

    "weekly patch")
        if [ -z "$ARG1" ]; then
            echo "❌ Missing version. Usage: run weekly patch <version>"
            echo "   Example: run weekly patch 260.12"
            exit 1
        fi
        echo "🚀 Running weekly patch for version $ARG1..."
        bash "$SCRIPT_DIR/weekly-patch.sh" "$ARG1"
        ;;

    "check builds")
        if [ -z "$ARG1" ]; then
            echo "❌ Missing version. Usage: run check builds <version>"
            echo "   Example: run check builds 260.12"
            exit 1
        fi
        echo "🔍 Checking builds for version $ARG1..."
        bash "$SCRIPT_DIR/check-builds.sh" "$ARG1" "$ARG2"
        ;;

    *)
        echo "❌ Unknown command: '$COMMAND $SUBCOMMAND'"
        usage
        exit 1
        ;;
esac
