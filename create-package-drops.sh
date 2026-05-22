#!/bin/bash

# GUS Package Drop Work Item Creation Script
# Usage: ./create-package-drops.sh <verticals> <version>

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <verticals> <version>"
    echo "Example: $0 CME 260.11"
    exit 1
fi

VERTICALS_INPUT="$1"
NEW_VERSION="$2"

IFS='/' read -ra VERTICALS <<< "$VERTICALS_INPUT"

VALID_VERTICALS="CME INS OS INS-FSC"

for vertical in "${VERTICALS[@]}"; do
    if ! echo "$VALID_VERTICALS" | grep -qw "$vertical"; then
        echo "Error: Invalid vertical"
        exit 1
    fi
done

SCRIPT_DIR="$(dirname "$0")"
SCHEDULE_FILE="$SCRIPT_DIR/release-schedule.json"
PACKAGE_DROP_CONFIG="$SCRIPT_DIR/package-drop-config.json"
RELEASE_NAMES="$SCRIPT_DIR/release-names.json"

if [ ! -f "$SCHEDULE_FILE" ] || [ ! -f "$PACKAGE_DROP_CONFIG" ] || [ ! -f "$RELEASE_NAMES" ]; then
    echo "Error: Required configuration files not found"
    exit 1
fi

# Check if POC assignments need verification (monthly check)
POC_CHECK_FILE="$SCRIPT_DIR/.last-poc-check"
CURRENT_DATE=$(date +%s)
THIRTY_DAYS=$((30 * 24 * 60 * 60))

if [ -f "$POC_CHECK_FILE" ]; then
    LAST_CHECK=$(cat "$POC_CHECK_FILE")
    DAYS_SINCE_CHECK=$(( (CURRENT_DATE - LAST_CHECK) / 86400 ))

    if [ $((CURRENT_DATE - LAST_CHECK)) -gt $THIRTY_DAYS ]; then
        echo "⚠️  POC assignments were last verified $DAYS_SINCE_CHECK days ago ($(date -r $LAST_CHECK +%Y-%m-%d))"
        echo "   Please verify Slack thread for any updates:"
        echo "   https://salesforce-internal.slack.com/archives/C02T6SW42MR/p1757298890285999"
        echo ""
        echo "   Current assignments:"
        echo "   - Assignee (IN POC): Amarendar Musham (005EE00000ba6uPYAQ)"
        echo "   - Product Owner: Vishal Trivedi (005B0000004lkO5IAI)"
        echo ""
        read -p "   Have you verified? Press Enter to continue or Ctrl+C to abort: "
        echo "$CURRENT_DATE" > "$POC_CHECK_FILE"
    fi
else
    # First time running - create the timestamp file
    echo "$CURRENT_DATE" > "$POC_CHECK_FILE"
fi

echo "========================================"
echo "GUS PACKAGE DROP WORK ITEM CREATION"
echo "========================================"
echo "Verticals: ${VERTICALS[@]}"
echo "Version: $NEW_VERSION"
echo "========================================"

DATES=$(jq -r ".\"$NEW_VERSION\" // empty" "$SCHEDULE_FILE")
if [ -z "$DATES" ]; then
    echo "Error: Version not found in schedule"
    exit 1
fi

LAST_MERGE=$(echo "$DATES" | jq -r '.last_merge')
IS_MONTHLY=$(jq -r ".\"$NEW_VERSION\".monthly // false" "$SCHEDULE_FILE")
SIGN_OFF=$(echo "$DATES" | jq -r '.sign_off')
RELEASE=$(echo "$DATES" | jq -r '.release')
RELEASE_SHORT=$(echo "$RELEASE" | sed -E 's/^[0-9]{4}-0?([0-9]{1,2})-0?([0-9]{1,2})$/\1\/\2/')
RELEASE_WITH_TIME="${RELEASE}T18:00:00.000+0000"
LAST_MERGE_TIME=$(echo "$DATES" | jq -r '.last_merge_time // "11:30 AM IST"')
SIGN_OFF_TIME=$(echo "$DATES" | jq -r '.sign_off_time // "03:00 PM IST"')

# Extract major version and get release name
MAJOR_VERSION=$(echo "$NEW_VERSION" | grep -oE '^[0-9]+')
RELEASE_NAME=$(jq -r ".\"$MAJOR_VERSION\" // empty" "$RELEASE_NAMES")

if [ -z "$RELEASE_NAME" ]; then
    echo "Error: Release name not found for major version $MAJOR_VERSION"
    echo "Please add it to $RELEASE_NAMES"
    exit 1
fi

# RF dates from sprint sheets (for scheduled build logic)
# If today > RF date, use next major release for scheduled build
TODAY=$(date +%Y-%m-%d)
RF_DATE=""
BUILD_MAJOR_VERSION=$MAJOR_VERSION

case "$MAJOR_VERSION" in
    260)
        RF_DATE="2025-12-18"
        ;;
    262)
        RF_DATE="2026-04-16"
        ;;
    264)
        RF_DATE="2026-08-13"
        ;;
esac

if [ ! -z "$RF_DATE" ] && [[ "$TODAY" > "$RF_DATE" ]]; then
    BUILD_MAJOR_VERSION=$((MAJOR_VERSION + 2))
    echo "Note: RF date ($RF_DATE) has passed, using next major release ($BUILD_MAJOR_VERSION) for scheduled build"
fi

# Calculate sprint from release date using sprint schedule mapping
SPRINT_NAME=""
PYTHON_SCRIPT=$(cat <<'PYTHON_EOF'
from datetime import datetime
import sys

def get_sprint_for_release(release_date_str):
    """Map release date to sprint based on 260, 262, 264 schedules"""
    release_date = datetime.strptime(release_date_str, '%Y-%m-%d')

    # Sprint schedules from Google Sheet (sheet names: 260 (US & IN), 262 (US & IN), 264 (US & IN))
    sprints_260 = [
        ("2025-08-04", "2025-08-22", "2025.08a"),
        ("2025-08-25", "2025-09-05", "2025.08b"),
        ("2025-09-08", "2025-09-19", "2025.09a"),
        ("2025-09-22", "2025-10-03", "2025.09b"),
        ("2025-10-06", "2025-10-17", "2025.10a"),
        ("2025-10-20", "2025-11-07", "2025.10b"),
        ("2025-11-10", "2025-11-21", "2025.11a"),
        ("2025-11-24", "2025-12-19", "2025.12a"),
    ]

    sprints_262 = [
        ("2025-11-24", "2025-12-19", "2025.12a"),
        ("2025-12-22", "2026-01-02", "2025.12b"),
        ("2026-01-05", "2026-01-16", "2026.01a"),
        ("2026-01-19", "2026-01-30", "2026.01b"),
        ("2026-02-02", "2026-02-13", "2026.02a"),
        ("2026-02-16", "2026-02-27", "2026.02b"),
        ("2026-03-02", "2026-03-13", "2026.03a"),
        ("2026-03-16", "2026-03-27", "2026.03b"),
        ("2026-03-30", "2026-04-17", "2026.04a"),
    ]

    sprints_264 = [
        ("2026-03-30", "2026-04-17", "2026.04a"),
        ("2026-04-20", "2026-05-01", "2026.04b"),
        ("2026-05-04", "2026-05-15", "2026.05a"),
        ("2026-05-18", "2026-05-29", "2026.05b"),
        ("2026-06-01", "2026-06-12", "2026.06a"),
        ("2026-06-15", "2026-06-26", "2026.06b"),
        ("2026-06-29", "2026-07-10", "2026.07a"),
        ("2026-07-13", "2026-07-24", "2026.07b"),
        ("2026-07-27", "2026-08-14", "2026.08a"),
    ]

    all_sprints = sprints_260 + sprints_262 + sprints_264

    for start_str, end_str, sprint_code in all_sprints:
        start = datetime.strptime(start_str, '%Y-%m-%d')
        end = datetime.strptime(end_str, '%Y-%m-%d')
        if start <= release_date <= end:
            return f"{sprint_code}-Industries Release Engineering - Skywalker"

    return None

if __name__ == '__main__':
    release_date = sys.argv[1]
    sprint = get_sprint_for_release(release_date)
    if sprint:
        print(sprint)
    else:
        sys.exit(1)
PYTHON_EOF
)

SPRINT_NAME=$(python3 -c "$PYTHON_SCRIPT" "$RELEASE" 2>/dev/null || echo "")

if [ -z "$SPRINT_NAME" ]; then
    echo "Warning: Could not calculate sprint for release date $RELEASE"
    read -p "Enter sprint name manually (or press Enter to skip): " SPRINT_NAME
else
    echo "Calculated Sprint: $SPRINT_NAME"
fi

# Query sprint ID if sprint name provided
SPRINT_ID=""
if [ ! -z "$SPRINT_NAME" ]; then
    SPRINT_QUERY=$(sf data query --target-org gus --query "SELECT Id FROM ADM_Sprint__c WHERE Name = '$SPRINT_NAME' LIMIT 1" --json)
    SPRINT_ID=$(echo "$SPRINT_QUERY" | jq -r '.result.records[0].Id // "null"')

    if [ "$SPRINT_ID" = "null" ]; then
        echo "Warning: Sprint '$SPRINT_NAME' not found in GUS"
        echo "Package drops will be created without sprint assignment"
        SPRINT_ID=""
    fi
fi

echo "Release: $RELEASE_NAME"
echo ""

declare -a WORKITEM_DETAILS

for i in "${!VERTICALS[@]}"; do
    VERTICAL="${VERTICALS[$i]}"
    echo "Processing $VERTICAL..."

    REF_WORKITEM_ID=$(jq -r ".verticals.\"$VERTICAL\".reference_workitem // empty" "$PACKAGE_DROP_CONFIG")
    if [ -z "$REF_WORKITEM_ID" ]; then
        echo "Error: No reference work item for $VERTICAL"
        exit 1
    fi

    REF_DATA=$(sf data query --target-org gus --query \
      "SELECT Subject__c, Type__c, Product_Tag__c, Scrum_Team__c, RecordTypeId \
       FROM ADM_Work__c WHERE Id = '$REF_WORKITEM_ID'" --json)

    REF_TYPE=$(echo "$REF_DATA" | jq -r '.result.records[0].Type__c')
    REF_PRODUCT_TAG=$(echo "$REF_DATA" | jq -r '.result.records[0].Product_Tag__c')
    REF_SCRUM_TEAM=$(echo "$REF_DATA" | jq -r '.result.records[0].Scrum_Team__c')
    REF_RECORDTYPE=$(echo "$REF_DATA" | jq -r '.result.records[0].RecordTypeId')

    # Query for Scheduled Build (use next major if RF passed)
    BUILD_NAME="Industries.$BUILD_MAJOR_VERSION"
    BUILD_DATA=$(sf data query --target-org gus --query \
      "SELECT Id FROM ADM_Build__c WHERE Name = '$BUILD_NAME' LIMIT 1" --json)
    BUILD_ID=$(echo "$BUILD_DATA" | jq -r '.result.records[0].Id // "null"')

    # Create new subject for package drop
    if [ "$IS_MONTHLY" = "true" ]; then
        NEW_SUBJECT="[Vlocity-$VERTICAL] Package drop for version $VERTICAL $NEW_VERSION Monthly"
    else
        NEW_SUBJECT="[Vlocity-$VERTICAL] Package drop for version $VERTICAL $NEW_VERSION"
    fi

    # Create details with relevant information
    NEW_DETAILS="<p>Build $VERTICAL package</p><p><br></p><ol><li>Create <span style=\"background-color: rgb(255, 255, 255); color: rgb(68, 68, 68);\">$NEW_VERSION </span>Patch branch from <span style=\"font-size: 14px;\">release-$MAJOR_VERSION.patch</span></li><li>Build package on the patch org</li></ol><p><span style=\"font-size: 11pt; font-family: Arial;\">Last merge : $LAST_MERGE, Sign off: $SIGN_OFF, Release : $RELEASE_SHORT</span></p>"

    WORKITEM_DETAILS[$i]="$VERTICAL|$NEW_SUBJECT|$NEW_DETAILS|$BUILD_ID|$REF_TYPE|$REF_PRODUCT_TAG|$REF_SCRUM_TEAM|$REF_RECORDTYPE"
    echo "  Ready: $NEW_SUBJECT"
done

echo ""
read -p "Create ${#VERTICALS[@]} package drop work items? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

echo "Creating..."
CREATED_WORKITEMS=()

# Package drop assignments (from Slack thread: https://salesforce-internal.slack.com/archives/C02T6SW42MR/p1757298890285999)
ASSIGNEE_ID="005EE00000ba6uPYAQ"  # Amarendar Musham (IN POC)
PO_ID="005B0000004lkO5IAI"  # Vishal Trivedi

for i in "${!VERTICALS[@]}"; do
    VERTICAL="${VERTICALS[$i]}"
    IFS='|' read -r V_NAME NEW_SUBJECT NEW_DETAILS BUILD_ID REF_TYPE REF_PRODUCT_TAG REF_SCRUM_TEAM REF_RECORDTYPE <<< "${WORKITEM_DETAILS[$i]}"

    VALUES="RecordTypeId='$REF_RECORDTYPE' Subject__c='$NEW_SUBJECT' Type__c='$REF_TYPE' Status__c='New' Assignee__c='$ASSIGNEE_ID' Product_Owner__c='$PO_ID' Product_Tag__c='$REF_PRODUCT_TAG' Scrum_Team__c='$REF_SCRUM_TEAM' Details__c='$NEW_DETAILS' Due_Date__c='$RELEASE_WITH_TIME'"

    # Add sprint if available
    if [ ! -z "$SPRINT_ID" ]; then
        VALUES="$VALUES Sprint__c='$SPRINT_ID'"
    fi

    # Add scheduled build if available
    if [ "$BUILD_ID" != "null" ]; then
        VALUES="$VALUES Scheduled_Build__c='$BUILD_ID'"
    fi

    CREATE_RESULT=$(sf data create record --target-org gus --sobject ADM_Work__c --values "$VALUES" --json 2>&1)

    if [ $? -eq 0 ]; then
        WORKITEM_ID=$(echo "$CREATE_RESULT" | jq -r '.result.id')
        W_DATA=$(sf data query --target-org gus --query "SELECT Name FROM ADM_Work__c WHERE Id = '$WORKITEM_ID'" --json)
        W_NUMBER=$(echo "$W_DATA" | jq -r '.result.records[0].Name')
        CREATED_WORKITEMS+=("$VERTICAL|$W_NUMBER|$WORKITEM_ID")
        echo "✅ $W_NUMBER"
    else
        echo "❌ Failed: $VERTICAL"
        echo "$CREATE_RESULT"
    fi
done

echo ""
echo "========================================"
echo "Created ${#CREATED_WORKITEMS[@]} package drop work items:"
for workitem in "${CREATED_WORKITEMS[@]}"; do
    IFS='|' read -r VERTICAL W_NUMBER WORKITEM_ID <<< "$workitem"
    echo "[$VERTICAL] $W_NUMBER"
    echo "  https://gus.lightning.force.com/lightning/r/ADM_Work__c/$WORKITEM_ID/view"
done
echo "========================================"

# Prepare Slack notifications - output for Claude to post
if [ ${#CREATED_WORKITEMS[@]} -gt 0 ]; then
    echo ""
    echo "========================================"
    echo "SLACK NOTIFICATIONS TO POST"
    echo "========================================"

    # Slack configuration - TEST MODE (posting to user DM)
    # Slack targets: DM to Aarti + release patch private channel
    SLACK_TARGET="U098NUEJ6G4"  # Aarti Somani (DM)
    SLACK_CHANNEL="G026TENPY74"  # #industries-vlocity-release_patch_private

    SLACK_DATA_FILE="$SCRIPT_DIR/.slack-post-data.json"
    echo "[" > "$SLACK_DATA_FILE"
    FIRST=true

    for workitem in "${CREATED_WORKITEMS[@]}"; do
        IFS='|' read -r VERTICAL W_NUMBER WORKITEM_ID <<< "$workitem"

        # Use Python helper to format message - DM + #industries-vlocity-release_patch_private
        SLACK_OUTPUT_DM=$(python3 "$SCRIPT_DIR/post-to-slack.py" "$SLACK_TARGET" "$VERTICAL" "$NEW_VERSION" "$W_NUMBER" "$LAST_MERGE" "$SIGN_OFF" "$RELEASE" "$LAST_MERGE_TIME" "$SIGN_OFF_TIME" "$IS_MONTHLY")
        SLACK_OUTPUT_CH=$(python3 "$SCRIPT_DIR/post-to-slack.py" "$SLACK_CHANNEL" "$VERTICAL" "$NEW_VERSION" "$W_NUMBER" "$LAST_MERGE" "$SIGN_OFF" "$RELEASE" "$LAST_MERGE_TIME" "$SIGN_OFF_TIME" "$IS_MONTHLY")

        if [ "$FIRST" = false ]; then
            echo "," >> "$SLACK_DATA_FILE"
        fi
        echo "$SLACK_OUTPUT_DM" >> "$SLACK_DATA_FILE"
        echo "," >> "$SLACK_DATA_FILE"
        echo "$SLACK_OUTPUT_CH" >> "$SLACK_DATA_FILE"
        FIRST=false

        echo "[$VERTICAL] $W_NUMBER → DM + #industries-vlocity-release_patch_private"
    done

    echo "]" >> "$SLACK_DATA_FILE"

    echo ""
    echo "📝 Slack post data saved to: $SLACK_DATA_FILE"
    echo "⚠️  IMPORTANT: Ask Claude to execute Slack posts with:"
    echo "   'Post the Slack notifications from $SLACK_DATA_FILE'"
    echo "========================================"
fi
