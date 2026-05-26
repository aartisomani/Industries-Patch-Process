#!/bin/bash
# ============================================================
# POST-DEPLOY-SLACK - Generate the deployment-day Slack message payload
#
# Usage: ./post-deploy-slack.sh <VERSION>
#
# Reads:
#   - patch-state.json for the Release record ID
#   - release-schedule.json for the deployment date
#   - .deploy-slack-data.json gets written for Claude/MCP to post
#
# After this runs, the slash command instructs Claude to:
#   1. Read .deploy-slack-data.json
#   2. Post the message to #industries-vlocity-release_patch_private
#   3. Save thread timestamp via:
#        python3 monitor-builds.py --version <VERSION> --add-deploy-thread <CHANNEL_ID> <THREAD_TS>
# ============================================================

set -e

VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$VERSION" ]; then
    echo "❌ Missing version. Usage: $0 <VERSION>"
    exit 1
fi

STATE_FILE="$SCRIPT_DIR/patch-state.json"
SCHEDULE_FILE="$SCRIPT_DIR/release-schedule.json"
OUTPUT_FILE="$SCRIPT_DIR/.deploy-slack-data.json"
SLACK_CHANNEL="G026TENPY74"  # #industries-vlocity-release_patch_private

# Look up Release record ID from state file
RELEASE_ID=$(jq -r ".\"$VERSION\".release_record_id // \"\"" "$STATE_FILE" 2>/dev/null)
RELEASE_NAME=$(jq -r ".\"$VERSION\".release_record_name // \"\"" "$STATE_FILE" 2>/dev/null)

if [ -z "$RELEASE_ID" ]; then
    echo "❌ No Release record ID found in patch-state.json for version $VERSION"
    echo ""
    echo "   First run:"
    echo "     ./find-release-record.sh $VERSION"
    echo "   Then save the ID:"
    echo "     python3 monitor-builds.py --version $VERSION --add-release-id <RELEASE_ID> <RELEASE_NAME>"
    exit 1
fi

# Look up release date
RELEASE_DATE=$(jq -r ".\"$VERSION\".release // \"\"" "$SCHEDULE_FILE" 2>/dev/null)
IS_MONTHLY=$(jq -r ".\"$VERSION\".monthly // false" "$SCHEDULE_FILE" 2>/dev/null)
PATCH_TYPE="Patch"
if [ "$IS_MONTHLY" = "true" ]; then
    PATCH_TYPE="Monthly Patch"
fi

RELEASE_URL="https://gus.lightning.force.com/lightning/r/ADM_Release__c/${RELEASE_ID}/view"

# Build the Slack message
# NOTE: Replace MESSAGE_BODY content once user provides the deployment template.
# This is a placeholder that follows the Friday format.
MESSAGE_BODY=$(cat <<EOF
\`\`\`
Starting deployment for ${PATCH_TYPE} ${VERSION}.
Release Record: ${RELEASE_NAME}
${RELEASE_URL}

Release Date: ${RELEASE_DATE}
RM: Aarti Somani
RE: Amarendar Musham

Sign-offs are being added to the Release record. Please confirm if any additional approvers needed.
\`\`\`
EOF
)

# Write payload for Claude to post
python3 <<PYEOF
import json
payload = {
    "channel_id": "$SLACK_CHANNEL",
    "version": "$VERSION",
    "release_id": "$RELEASE_ID",
    "release_name": "$RELEASE_NAME",
    "release_url": "$RELEASE_URL",
    "patch_type": "$PATCH_TYPE",
    "message": """$MESSAGE_BODY""",
    "thread_reply": "<@U08TFFLU9HP> FYA — deployment kickoff"
}
with open("$OUTPUT_FILE", "w") as f:
    json.dump(payload, f, indent=2)
print("✅ Wrote $OUTPUT_FILE")
PYEOF

echo ""
echo "Next: Claude will read $OUTPUT_FILE and post to Slack via MCP."
