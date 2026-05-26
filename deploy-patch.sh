#!/bin/bash
# ============================================================
# DEPLOY-PATCH - Orchestrator for deployment-day workflow
#
# Stateless: each step queries GUS directly for the Release record by version.
# Does NOT use patch-state.json.
#
# Steps:
#   1. Generate the deployment-day Slack payload (Claude posts via MCP)
#   2. Add per-vertical sign-offs to the Release record
#
# Usage:
#   ./deploy-patch.sh <VERSION>             Run all steps
#   ./deploy-patch.sh <VERSION> slack       Step 1 only — generate Slack payload
#   ./deploy-patch.sh <VERSION> signoffs    Step 2 only — add sign-offs
#
# Examples:
#   ./deploy-patch.sh 262.8
#   ./deploy-patch.sh 262.8 signoffs
#
# Optional: to manually verify which Release record will be picked up:
#   ./find-release-record.sh <VERSION>
# ============================================================

set -e

VERSION="$1"
STEP="$2"  # optional: slack | signoffs
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$VERSION" ]; then
    echo "❌ Missing version. Usage: $0 <VERSION> [slack|signoffs]"
    exit 1
fi

echo "========================================"
echo "DEPLOYMENT WORKFLOW: $VERSION"
echo "========================================"

# ── STEP 1: Slack ─────────────────────────────────────────
if [ -z "$STEP" ] || [ "$STEP" = "slack" ]; then
    echo ""
    echo "========== STEP 1: GENERATE DEPLOYMENT SLACK =========="
    bash "$SCRIPT_DIR/post-deploy-slack.sh" "$VERSION"
    if [ $? -ne 0 ]; then
        echo "❌ Failed to generate Slack payload"
        exit 1
    fi
    echo ""
    echo "ℹ️  .deploy-slack-data.json written. Claude (via SKILL.md instructions) will post it."
    if [ "$STEP" = "slack" ]; then exit 0; fi
fi

# ── STEP 2: Sign-offs ─────────────────────────────────────
if [ -z "$STEP" ] || [ "$STEP" = "signoffs" ]; then
    echo ""
    echo "========== STEP 2: ADD SIGN-OFFS TO RELEASE =========="
    bash "$SCRIPT_DIR/add-signoffs.sh" "$VERSION"
fi

echo ""
echo "========================================"
echo "DEPLOYMENT WORKFLOW COMPLETE for $VERSION"
echo "========================================"
