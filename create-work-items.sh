#!/bin/bash

# GUS Work Item Creation Script - Clone from Reference
# Usage: ./create-work-items.sh <verticals> <version> <type>

set -e

if [ $# -lt 3 ]; then
    echo "Usage: $0 <verticals> <version> <type>"
    echo "Example: $0 CME 260.11 Patch"
    exit 1
fi

VERTICALS_INPUT="$1"
NEW_VERSION="$2"
TYPE="$3"

IFS='/' read -ra VERTICALS <<< "$VERTICALS_INPUT"

VALID_VERTICALS="CME INS OS INS-FSC"
VALID_TYPES="Patch ERR"

if ! echo "$VALID_TYPES" | grep -qw "$TYPE"; then
    echo "Error: Invalid type"
    exit 1
fi

for vertical in "${VERTICALS[@]}"; do
    if ! echo "$VALID_VERTICALS" | grep -qw "$vertical"; then
        echo "Error: Invalid vertical"
        exit 1
    fi
done

SCRIPT_DIR="$(dirname "$0")"
CONFIG_FILE="$SCRIPT_DIR/epic-config.json"
SCHEDULE_FILE="$SCRIPT_DIR/release-schedule.json"
WORKITEM_CONFIG="$SCRIPT_DIR/workitem-config.json"
RELEASE_NAMES="$SCRIPT_DIR/release-names.json"
TECH_WRITER_CONFIG="$SCRIPT_DIR/tech-writer-config.json"

if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$SCHEDULE_FILE" ] || [ ! -f "$WORKITEM_CONFIG" ] || [ ! -f "$RELEASE_NAMES" ] || [ ! -f "$TECH_WRITER_CONFIG" ]; then
    echo "Error: Required configuration files not found"
    exit 1
fi

echo "========================================"
echo "GUS WORK ITEM BULK CREATION"
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

# Extract major version (e.g., 260 from 260.11) and get release name
MAJOR_VERSION=$(echo "$NEW_VERSION" | grep -oE '^[0-9]+')
RELEASE_NAME=$(jq -r ".\"$MAJOR_VERSION\" // empty" "$RELEASE_NAMES")

if [ -z "$RELEASE_NAME" ]; then
    echo "Error: Release name not found for major version $MAJOR_VERSION"
    echo "Please add it to $RELEASE_NAMES"
    exit 1
fi

echo "Dates: $LAST_MERGE / $SIGN_OFF / $RELEASE_SHORT"
echo "Release: $RELEASE_NAME"
echo ""

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
        echo "Work items will be created without sprint assignment"
        SPRINT_ID=""
    fi
fi

echo ""

declare -a WORKITEM_DETAILS

for i in "${!VERTICALS[@]}"; do
    VERTICAL="${VERTICALS[$i]}"
    echo "Processing $VERTICAL..."

    REF_WORKITEM_ID=$(jq -r ".verticals.\"$VERTICAL\".patch_reference_workitem // empty" "$WORKITEM_CONFIG")
    if [ -z "$REF_WORKITEM_ID" ]; then
        echo "Error: No reference work item for $VERTICAL"
        exit 1
    fi

    REF_DATA=$(sf data query --target-org gus --query \
      "SELECT Subject__c, Type__c, Status__c, Assignee__c, Product_Tag__c, Scrum_Team__c, RecordTypeId \
       FROM ADM_Work__c WHERE Id = '$REF_WORKITEM_ID'" --json)

    REF_TYPE=$(echo "$REF_DATA" | jq -r '.result.records[0].Type__c')
    REF_STATUS=$(echo "$REF_DATA" | jq -r '.result.records[0].Status__c')
    REF_ASSIGNEE=$(echo "$REF_DATA" | jq -r '.result.records[0].Assignee__c')
    REF_PRODUCT_TAG=$(echo "$REF_DATA" | jq -r '.result.records[0].Product_Tag__c')
    REF_SCRUM_TEAM=$(echo "$REF_DATA" | jq -r '.result.records[0].Scrum_Team__c')
    REF_SUBJECT=$(echo "$REF_DATA" | jq -r '.result.records[0].Subject__c')
    REF_RECORDTYPE=$(echo "$REF_DATA" | jq -r '.result.records[0].RecordTypeId')

    EPIC_NAME_PREFIX="Industries.$VERTICAL $NEW_VERSION"
    EPIC_DATA=$(sf data query --target-org gus --query \
      "SELECT Id, Name FROM ADM_Epic__c WHERE Name LIKE '${EPIC_NAME_PREFIX}%${TYPE}%' ORDER BY CreatedDate DESC LIMIT 1" --json)
    EPIC_ID=$(echo "$EPIC_DATA" | jq -r '.result.records[0].Id // "null"')
    EPIC_NAME=$(echo "$EPIC_DATA" | jq -r '.result.records[0].Name // "null"')

    if [ "$EPIC_ID" = "null" ]; then
        echo "Error: Epic not found matching: ${EPIC_NAME_PREFIX}*${TYPE}*"
        exit 1
    fi
    echo "  Using Epic: $EPIC_NAME ($EPIC_ID)"

    BUILD_NAME="Industries.$VERTICAL $NEW_VERSION"
    BUILD_DATA=$(sf data query --target-org gus --query \
      "SELECT Id FROM ADM_Build__c WHERE Name = '$BUILD_NAME' LIMIT 1" --json)
    BUILD_ID=$(echo "$BUILD_DATA" | jq -r '.result.records[0].Id // "null"')

    # Create new subject with correct version and release name
    if [ "$IS_MONTHLY" = "true" ]; then
        NEW_SUBJECT="[Vlocity-$VERTICAL] Monthly Patch $VERTICAL $NEW_VERSION ($RELEASE_NAME )"
    else
        NEW_SUBJECT="[Vlocity-$VERTICAL] Patch $VERTICAL $NEW_VERSION ($RELEASE_NAME )"
    fi
    DETAILS="<p>Patch Number $NEW_VERSION</p><p><br></p><p>Last merge : $LAST_MERGE, Sign off: $SIGN_OFF, Release : $RELEASE_SHORT</p>"

    # Get tech writer for this vertical
    TECH_WRITER_ID=$(jq -r ".verticals.\"$VERTICAL\".tech_writer_id // empty" "$TECH_WRITER_CONFIG")
    CHATTER_MENTION_ID=$(jq -r ".verticals.\"$VERTICAL\".chatter_mention_id // empty" "$TECH_WRITER_CONFIG")
    CHATTER_MESSAGE=$(jq -r ".verticals.\"$VERTICAL\".chatter_message // empty" "$TECH_WRITER_CONFIG")

    WORKITEM_DETAILS[$i]="$VERTICAL|$EPIC_ID|$NEW_SUBJECT|$DETAILS|$BUILD_ID|$REF_TYPE|$REF_STATUS|$REF_ASSIGNEE|$REF_PRODUCT_TAG|$REF_SCRUM_TEAM|$REF_RECORDTYPE|$RELEASE_WITH_TIME|$TECH_WRITER_ID|$CHATTER_MENTION_ID|$CHATTER_MESSAGE"
    echo "  Ready: $NEW_SUBJECT"
done

echo ""
read -p "Create ${#VERTICALS[@]} work items? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

echo "Creating..."
CREATED_WORKITEMS=()

for i in "${!VERTICALS[@]}"; do
    VERTICAL="${VERTICALS[$i]}"
    IFS='|' read -r V_NAME EPIC_ID NEW_SUBJECT DETAILS BUILD_ID REF_TYPE REF_STATUS REF_ASSIGNEE REF_PRODUCT_TAG REF_SCRUM_TEAM REF_RECORDTYPE DUE_DATE TECH_WRITER_ID CHATTER_MENTION_ID CHATTER_MESSAGE <<< "${WORKITEM_DETAILS[$i]}"

    VALUES="RecordTypeId='$REF_RECORDTYPE' Subject__c='$NEW_SUBJECT' Type__c='$REF_TYPE' Status__c='New' Epic__c='$EPIC_ID' Assignee__c='$REF_ASSIGNEE' Product_Tag__c='$REF_PRODUCT_TAG' Scrum_Team__c='$REF_SCRUM_TEAM' Details__c='$DETAILS' Due_Date__c='$DUE_DATE'"

    if [ "$BUILD_ID" != "null" ]; then
        VALUES="$VALUES Scheduled_Build__c='$BUILD_ID'"
    fi

    # Add sprint if available
    if [ ! -z "$SPRINT_ID" ]; then
        VALUES="$VALUES Sprint__c='$SPRINT_ID'"
    fi

    # Add tech writer if configured
    if [ ! -z "$TECH_WRITER_ID" ]; then
        VALUES="$VALUES Tech_Writer__c='$TECH_WRITER_ID'"
    fi

    CREATE_RESULT=$(sf data create record --target-org gus --sobject ADM_Work__c --values "$VALUES" --json 2>&1)

    if [ $? -eq 0 ]; then
        WORKITEM_ID=$(echo "$CREATE_RESULT" | jq -r '.result.id')
        W_DATA=$(sf data query --target-org gus --query "SELECT Name FROM ADM_Work__c WHERE Id = '$WORKITEM_ID'" --json)
        W_NUMBER=$(echo "$W_DATA" | jq -r '.result.records[0].Name')
        CREATED_WORKITEMS+=("$VERTICAL|$W_NUMBER|$WORKITEM_ID")
        echo "✅ $W_NUMBER"

        # Post Chatter comment if configured (for OS) - uses Chatter REST API for proper @mention
        if [ ! -z "$CHATTER_MENTION_ID" ] && [ ! -z "$CHATTER_MESSAGE" ]; then
            python3 -c "
import json, subprocess
body = {
    'feedElementType': 'FeedItem',
    'subjectId': '$WORKITEM_ID',
    'body': {'messageSegments': [
        {'type': 'Mention', 'id': '$CHATTER_MENTION_ID'},
        {'type': 'Text', 'text': ' $CHATTER_MESSAGE'}
    ]}
}
r = subprocess.run(['sf','api','request','rest','--target-org','gus',
    '/services/data/v64.0/chatter/feed-elements','--method','POST',
    '--body', json.dumps(body)], capture_output=True, text=True)
print('ok' if '"id"' in r.stdout else r.stderr[:200])
" > /dev/null 2>&1
            echo "   📝 Chatter: Mentioned via proper @mention"
        fi
    else
        echo "❌ Failed: $VERTICAL"
    fi
done

echo ""
echo "========================================"
echo "Created ${#CREATED_WORKITEMS[@]} work items:"
for workitem in "${CREATED_WORKITEMS[@]}"; do
    IFS='|' read -r VERTICAL W_NUMBER WORKITEM_ID <<< "$workitem"
    echo "[$VERTICAL] $W_NUMBER"
    echo "  https://gus.lightning.force.com/lightning/r/ADM_Work__c/$WORKITEM_ID/view"
done
echo "========================================"

# ── Save work item IDs to patch-state.json for build monitor ──────────────
STATE_FILE="$SCRIPT_DIR/patch-state.json"
if [ ${#CREATED_WORKITEMS[@]} -gt 0 ]; then
    echo ""
    echo "💾 Saving work item IDs to patch-state.json..."

    # Bootstrap file if it doesn't exist
    if [ ! -f "$STATE_FILE" ]; then
        echo "{}" > "$STATE_FILE"
    fi

    for workitem in "${CREATED_WORKITEMS[@]}"; do
        IFS='|' read -r VERTICAL W_NUMBER WORKITEM_ID <<< "$workitem"
        # Upsert .["$NEW_VERSION"].work_items["$VERTICAL"]
        UPDATED=$(jq \
            --arg ver "$NEW_VERSION" \
            --arg vert "$VERTICAL" \
            --arg wid "$WORKITEM_ID" \
            --arg wnum "$W_NUMBER" \
            '.[$ver].work_items[$vert] = {"id": $wid, "name": $wnum}' \
            "$STATE_FILE")
        echo "$UPDATED" > "$STATE_FILE"
    done
    echo "✅ patch-state.json updated"
fi

# ── Step: Add CAB Patch Candidate Work Items as Child Work Records ─────────
echo ""
echo "========================================"
echo "ADDING CHILD WORK RECORDS FROM CAB PATCH REPORT"
echo "========================================"

# Map vertical name to CAB Scheduled_Build_Ref patterns (bash 3.2 compatible)
get_cab_filter() {
    case "$1" in
        CME)     echo "Industries.CME" ;;
        INS)     echo "Industries.INS" ;;
        OS)      echo "Industries.OS" ;;
        INS-FSC) echo "Industries.INS" ;;
        *)       echo "" ;;
    esac
}

for workitem in "${CREATED_WORKITEMS[@]}"; do
    IFS='|' read -r VERTICAL W_NUMBER RM_WORKITEM_ID <<< "$workitem"

    CAB_FILTER=$(get_cab_filter "$VERTICAL")

    # Special handling for INS-FSC — filter by FSC too
    if [ "$VERTICAL" == "INS-FSC" ]; then
        CAB_QUERY="SELECT Id, Name, Work__c FROM CAB_Patch_Candidate__c WHERE Scheduled_Build_Ref__c LIKE '%${NEW_VERSION}%' AND Scheduled_Build_Ref__c LIKE '%Industries.INS%FSC%' AND Stage__c IN ('Awaiting Approval', 'Pending Release', 'Close') AND Work__c != null"
    else
        CAB_QUERY="SELECT Id, Name, Work__c FROM CAB_Patch_Candidate__c WHERE Scheduled_Build_Ref__c LIKE '%${NEW_VERSION}%' AND Scheduled_Build_Ref__c LIKE '%${CAB_FILTER}%' AND (NOT Scheduled_Build_Ref__c LIKE '%FSC%') AND Stage__c IN ('Awaiting Approval', 'Pending Release', 'Close') AND Work__c != null"
    fi

    echo ""
    echo "[$VERTICAL] Querying CAB Patch Candidates → RM ticket: $W_NUMBER"
    CAB_RESULTS=$(sf data query --target-org gus --query "$CAB_QUERY" --json 2>/dev/null)
    CAB_COUNT=$(echo "$CAB_RESULTS" | jq '.result.totalSize')

    if [ "$CAB_COUNT" -eq 0 ]; then
        echo "  ⚠️  No CAB Patch Candidates found for $VERTICAL $NEW_VERSION"
        continue
    fi

    echo "  Found $CAB_COUNT CAB candidate(s) — adding as child work records..."

    CHILD_SUCCESS=0
    CHILD_FAIL=0

    while read -r row; do
        CAB_NAME=$(echo "$row" | jq -r '.Name')
        CHILD_WI_ID=$(echo "$row" | jq -r '.Work__c')

        # Get child WI number for display
        CHILD_WI_DATA=$(sf data query --target-org gus --query "SELECT Name FROM ADM_Work__c WHERE Id = '$CHILD_WI_ID'" --json 2>/dev/null)
        CHILD_WI_NUMBER=$(echo "$CHILD_WI_DATA" | jq -r '.result.records[0].Name // "unknown"')

        # Create ADM_Parent_Work__c record
        RESULT=$(sf data create record \
            --target-org gus \
            --sobject ADM_Parent_Work__c \
            --values "Parent_Work__c='$RM_WORKITEM_ID' Child_Work__c='$CHILD_WI_ID'" \
            --json 2>/dev/null)

        STATUS=$(echo "$RESULT" | jq -r '.status')
        if [ "$STATUS" == "0" ]; then
            echo "  ✅ Added child: $CHILD_WI_NUMBER ($CAB_NAME)"
            CHILD_SUCCESS=$((CHILD_SUCCESS + 1))
        else
            ERROR_MSG=$(echo "$RESULT" | jq -r '.message // "unknown error"')
            # Check if it's a duplicate (already linked)
            if echo "$ERROR_MSG" | grep -qi "duplicate\|already exists"; then
                echo "  ⏩ Already linked: $CHILD_WI_NUMBER ($CAB_NAME)"
            else
                echo "  ❌ Failed to add $CHILD_WI_NUMBER: $ERROR_MSG"
                CHILD_FAIL=$((CHILD_FAIL + 1))
            fi
        fi
    done < <(echo "$CAB_RESULTS" | jq -c '.result.records[]')

    echo "  [$VERTICAL] Summary: $CHILD_SUCCESS added, $CHILD_FAIL failed"
done

echo ""
echo "========================================"
echo "✅ CHILD WORK RECORDS COMPLETE"
echo "========================================"
