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

if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$SCHEDULE_FILE" ] || [ ! -f "$WORKITEM_CONFIG" ]; then
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
SIGN_OFF=$(echo "$DATES" | jq -r '.sign_off')
RELEASE=$(echo "$DATES" | jq -r '.release')
RELEASE_SHORT=$(echo "$RELEASE" | sed -E 's/^[0-9]{4}-0?([0-9]{1,2})-0?([0-9]{1,2})$/\1\/\2/')

echo "Dates: $LAST_MERGE / $SIGN_OFF / $RELEASE_SHORT"
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

    EPIC_NAME="Industries.$VERTICAL $NEW_VERSION $TYPE"
    EPIC_DATA=$(sf data query --target-org gus --query \
      "SELECT Id FROM ADM_Epic__c WHERE Name = '$EPIC_NAME' LIMIT 1" --json)
    EPIC_ID=$(echo "$EPIC_DATA" | jq -r '.result.records[0].Id // "null"')

    if [ "$EPIC_ID" = "null" ]; then
        echo "Error: Epic not found: $EPIC_NAME"
        exit 1
    fi

    BUILD_NAME="Industries.$VERTICAL $NEW_VERSION"
    BUILD_DATA=$(sf data query --target-org gus --query \
      "SELECT Id FROM ADM_Build__c WHERE Name = '$BUILD_NAME' LIMIT 1" --json)
    BUILD_ID=$(echo "$BUILD_DATA" | jq -r '.result.records[0].Id // "null"')

    OLD_VERSION=$(echo "$REF_SUBJECT" | grep -oE '[0-9]+\.[0-9]+')
    NEW_SUBJECT=$(echo "$REF_SUBJECT" | sed "s/$OLD_VERSION/$NEW_VERSION/g")
    DETAILS="<p>Patch Number $NEW_VERSION</p><p><br></p><p>Last merge : $LAST_MERGE, Sign off: $SIGN_OFF, Release : $RELEASE_SHORT</p>"

    WORKITEM_DETAILS[$i]="$VERTICAL|$EPIC_ID|$NEW_SUBJECT|$DETAILS|$BUILD_ID|$REF_TYPE|$REF_STATUS|$REF_ASSIGNEE|$REF_PRODUCT_TAG|$REF_SCRUM_TEAM|$REF_RECORDTYPE"
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
    IFS='|' read -r V_NAME EPIC_ID NEW_SUBJECT DETAILS BUILD_ID REF_TYPE REF_STATUS REF_ASSIGNEE REF_PRODUCT_TAG REF_SCRUM_TEAM REF_RECORDTYPE <<< "${WORKITEM_DETAILS[$i]}"

    VALUES="RecordTypeId='$REF_RECORDTYPE' Subject__c='$NEW_SUBJECT' Type__c='$REF_TYPE' Status__c='$REF_STATUS' Epic__c='$EPIC_ID' Assignee__c='$REF_ASSIGNEE' Product_Tag__c='$REF_PRODUCT_TAG' Scrum_Team__c='$REF_SCRUM_TEAM' Details__c='$DETAILS'"

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
