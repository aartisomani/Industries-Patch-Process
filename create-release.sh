#!/bin/bash

# Master script to create complete release: Epics + Patch Work Items + Package Drops
# Usage: ./create-release.sh <verticals> <version> <type>
# Example: ./create-release.sh CME/INS/OS/INS-FSC 260.11 Patch

set -e

if [ $# -lt 3 ]; then
    echo "Usage: $0 <verticals> <version> <type>"
    echo "Example: $0 CME/INS/OS/INS-FSC 260.11 Patch"
    exit 1
fi

VERTICALS="$1"
VERSION="$2"
TYPE="$3"

SCRIPT_DIR="$(dirname "$0")"

echo "========================================"
echo "GUS RELEASE CREATION - COMPLETE FLOW"
echo "========================================"
echo "Verticals: $VERTICALS"
echo "Version: $VERSION"
echo "Type: $TYPE"
echo "========================================"
echo ""

# Sync release schedule from live Non Core sheet
python3 "$SCRIPT_DIR/sync-schedule.py"

# Step 1: Create Epics
echo "========== STEP 1: CREATING EPICS =========="
yes | "$SCRIPT_DIR/clone-epic-v3.sh" "$VERTICALS" "$VERSION" "$TYPE"
if [ $? -ne 0 ]; then
    echo "❌ Epic creation failed. Aborting."
    exit 1
fi
echo ""

# Step 2: Create Patch Work Items
echo "========== STEP 2: CREATING PATCH WORK ITEMS =========="
yes | "$SCRIPT_DIR/create-work-items.sh" "$VERTICALS" "$VERSION" "$TYPE"
if [ $? -ne 0 ]; then
    echo "❌ Patch work item creation failed. Aborting."
    exit 1
fi
echo ""

# Step 3: Create Package Drop Work Items
echo "========== STEP 3: CREATING PACKAGE DROP WORK ITEMS =========="
# NOTE: Not piped through yes - POC verification prompt must be answered by a human
"$SCRIPT_DIR/create-package-drops.sh" "$VERTICALS" "$VERSION"
if [ $? -ne 0 ]; then
    echo "❌ Package drop work item creation failed. Aborting."
    exit 1
fi
echo ""

echo "========================================"
echo "✅ RELEASE CREATION COMPLETE"
echo "========================================"
echo ""
echo "Summary:"
echo "  ✅ Epics created for $VERTICALS"
echo "  ✅ Patch work items created"
echo "  ✅ Package drop work items created"
echo ""
echo "📝 Slack notifications prepared"
echo "   File: $SCRIPT_DIR/.slack-post-data.json"
echo ""
echo "⚠️  NEXT STEP: Ask Claude to post Slack notifications"
echo "   Command: Post the Slack notifications from $SCRIPT_DIR/.slack-post-data.json"
echo "========================================"
