#!/bin/bash

# GUS Epic Cloning Script - Multi-Vertical Support
# Usage: ./clone-epic-v3.sh <verticals> <version> <type>
# Example: ./clone-epic-v3.sh CME 260.11 Patch
# Example: ./clone-epic-v3.sh CME/INS/OS 260.11 Patch
# Example: ./clone-epic-v3.sh CME/INS/OS/INS-FSC 260.11 Patch

set -e

if [ $# -lt 3 ]; then
    echo "Usage: $0 <verticals> <version> <type>"
    echo ""
    echo "Parameters:"
    echo "  verticals: Single or multiple verticals separated by /"
    echo "             Examples: CME  or  CME/INS  or  CME/INS/OS/INS-FSC"
    echo "  version:   e.g., 260.11"
    echo "  type:      Patch | ERR"
    echo ""
    echo "Examples:"
    echo "  $0 CME 260.11 Patch"
    echo "  $0 CME/INS 260.11 Patch"
    echo "  $0 CME/INS/OS/INS-FSC 260.11 Patch"
    exit 1
fi

VERTICALS_INPUT="$1"
NEW_VERSION="$2"
TYPE="$3"

# Split verticals by /
IFS='/' read -ra VERTICALS <<< "$VERTICALS_INPUT"

# Validate inputs
VALID_VERTICALS="CME INS OS INS-FSC"
VALID_TYPES="Patch ERR"

# Validate type
if ! echo "$VALID_TYPES" | grep -qw "$TYPE"; then
    echo "Error: Invalid type '$TYPE'"
    echo "Valid types: $VALID_TYPES"
    exit 1
fi

# Validate all verticals
for vertical in "${VERTICALS[@]}"; do
    if ! echo "$VALID_VERTICALS" | grep -qw "$vertical"; then
        echo "Error: Invalid vertical '$vertical'"
        echo "Valid verticals: $VALID_VERTICALS"
        exit 1
    fi
done

# Configuration files
SCRIPT_DIR="$(dirname "$0")"
CONFIG_FILE="$SCRIPT_DIR/epic-config.json"
SCHEDULE_FILE="$SCRIPT_DIR/release-schedule.json"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found: $CONFIG_FILE"
    echo "Please create the file. See epic-config-example.json for format."
    exit 1
fi

# Check if schedule file exists
if [ ! -f "$SCHEDULE_FILE" ]; then
    echo "Error: Release schedule file not found: $SCHEDULE_FILE"
    echo "Please create the file. See release-schedule-example.json for format."
    exit 1
fi

echo "========================================"
echo "GUS EPIC BULK CREATION"
echo "========================================"
echo "Verticals: ${VERTICALS[@]}"
echo "Version: $NEW_VERSION"
echo "Type: $TYPE"
echo "========================================"
echo ""

# Get dates for the new version from schedule file
DATES=$(jq -r ".\"$NEW_VERSION\" // empty" "$SCHEDULE_FILE")
if [ -z "$DATES" ]; then
    echo "Error: Version $NEW_VERSION not found in release schedule"
    echo "Available versions:"
    jq -r 'keys[]' "$SCHEDULE_FILE"
    exit 1
fi

START_DATE=$(echo "$DATES" | jq -r '.start')
IS_MONTHLY=$(jq -r ".\"$NEW_VERSION\".monthly // false" "$SCHEDULE_FILE")
LAST_MERGE=$(echo "$DATES" | jq -r '.last_merge')
SIGN_OFF=$(echo "$DATES" | jq -r '.sign_off')
RELEASE=$(echo "$DATES" | jq -r '.release')

# Extract MM/DD format from release date for Health Comments
RELEASE_SHORT=$(echo "$RELEASE" | sed -E 's/^[0-9]{4}-0?([0-9]{1,2})-0?([0-9]{1,2})$/\1\/\2/')

echo "📅 Dates from schedule:"
echo "  Start Date: $START_DATE"
echo "  Last Merge: $LAST_MERGE"
echo "  Sign Off: $SIGN_OFF"
echo "  Release: $RELEASE"
echo ""

# Note: Scheduled Build is not set automatically - leave it empty for manual assignment

# Create Epic Health Comments
HEALTH_COMMENTS="Last merge: $LAST_MERGE, Sign off: $SIGN_OFF, Release: $RELEASE_SHORT"

echo ""
echo "========================================"
echo "PREVIEW - Will Create ${#VERTICALS[@]} Epic(s)"
echo "========================================"

# Array to store epic details for preview
declare -a EPIC_PREVIEWS
declare -a EPIC_DETAILS

# Process each vertical
for i in "${!VERTICALS[@]}"; do
    VERTICAL="${VERTICALS[$i]}"

    echo ""
    echo "[$((i+1))/${#VERTICALS[@]}] Processing $VERTICAL..."

    # Handle different types
    if [ "$TYPE" = "Patch" ]; then
        # Get reference epic for this vertical
        REF_EPIC_ID=$(jq -r ".verticals.\"$VERTICAL\".patch_reference_epic // empty" "$CONFIG_FILE")

        if [ -z "$REF_EPIC_ID" ]; then
            echo "❌ Error: No patch reference epic configured for vertical $VERTICAL"
            echo "Please add it to $CONFIG_FILE"
            exit 1
        fi

        echo "   Reference epic: $REF_EPIC_ID"

        # Fetch source epic details
        SOURCE_DATA=$(sf data query --target-org gus --query \
          "SELECT Name, Description__c, OwnerId, RecordTypeId, Category__c, Team__c, \
           Priority__c, Epic_Phase__c, Development_Lead__c, Quality_Lead__c, \
           Product_Owner__c, Project__c \
           FROM ADM_Epic__c WHERE Id = '$REF_EPIC_ID'" --json)

        if [ $? -ne 0 ]; then
            echo "❌ Error: Failed to fetch reference epic for $VERTICAL"
            exit 1
        fi

        # Extract fields
        OWNER_ID=$(echo "$SOURCE_DATA" | jq -r '.result.records[0].OwnerId')
        RECORD_TYPE_ID=$(echo "$SOURCE_DATA" | jq -r '.result.records[0].RecordTypeId')
        CATEGORY=$(echo "$SOURCE_DATA" | jq -r '.result.records[0].Category__c')
        PROJECT_ID=$(echo "$SOURCE_DATA" | jq -r '.result.records[0].Project__c')
        EPIC_PHASE=$(echo "$SOURCE_DATA" | jq -r '.result.records[0].Epic_Phase__c')
        DESCRIPTION=$(echo "$SOURCE_DATA" | jq -r '.result.records[0].Description__c')
        OLD_NAME=$(echo "$SOURCE_DATA" | jq -r '.result.records[0].Name')

        # Extract version pattern and create new name
        OLD_VERSION=$(echo "$OLD_NAME" | grep -oE '[0-9]+\.[0-9]+')
        NEW_NAME=$(echo "$OLD_NAME" | sed "s/$OLD_VERSION/$NEW_VERSION/g")
        if [ "$IS_MONTHLY" = "true" ]; then
            NEW_NAME=$(echo "$NEW_NAME" | sed "s/ Patch$/ Monthly Patch/")
        fi

    elif [ "$TYPE" = "ERR" ]; then
        echo "❌ ERR type epics are not yet implemented."
        echo "This feature will be added once ERR requirements are defined."
        exit 1
    fi

    echo "   New Epic Name: $NEW_NAME"

    # Store epic details for creation
    EPIC_DETAILS[$i]="$VERTICAL|$NEW_NAME|$DESCRIPTION|$OWNER_ID|$RECORD_TYPE_ID|$CATEGORY|$PROJECT_ID|$EPIC_PHASE"

    # Store preview
    EPIC_PREVIEWS[$i]="[$((i+1))] $NEW_NAME
    Category: $CATEGORY
    Project ID: $PROJECT_ID"
done

# Show consolidated preview
echo ""
echo "========================================"
echo "FINAL PREVIEW"
echo "========================================"
for preview in "${EPIC_PREVIEWS[@]}"; do
    echo "$preview"
    echo ""
done
echo "Common to all epics:"
echo "  Start Date: $START_DATE"
echo "  End Date: $RELEASE"
echo "  Health: New"
echo "  Health Comments: $HEALTH_COMMENTS"
echo "  Scheduled Build: (not set - assign manually)"
echo "========================================"
echo ""

read -p "Create these ${#VERTICALS[@]} epic(s)? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Create all epics
echo ""
echo "========================================"
echo "CREATING EPICS"
echo "========================================"

CREATED_EPICS=()
FAILED_EPICS=()

for i in "${!VERTICALS[@]}"; do
    VERTICAL="${VERTICALS[$i]}"

    # Parse stored details
    IFS='|' read -r V_NAME NEW_NAME DESCRIPTION OWNER_ID RECORD_TYPE_ID CATEGORY PROJECT_ID EPIC_PHASE <<< "${EPIC_DETAILS[$i]}"

    echo ""
    echo "[$((i+1))/${#VERTICALS[@]}] Creating epic for $VERTICAL..."

    # Create the epic
    CREATE_RESULT=$(sf data create record --target-org gus --sobject ADM_Epic__c --values \
      "Name='$NEW_NAME' \
       Description__c='$DESCRIPTION' \
       OwnerId='$OWNER_ID' \
       RecordTypeId='$RECORD_TYPE_ID' \
       Category__c='$CATEGORY' \
       Health__c='New' \
       Epic_Phase__c='$EPIC_PHASE' \
       Project__c='$PROJECT_ID' \
       Start_Date__c='$START_DATE' \
       End_Date__c='$RELEASE' \
       Epic_Health_Comments__c='$HEALTH_COMMENTS'" --json 2>&1)

    if [ $? -eq 0 ]; then
        NEW_EPIC_ID=$(echo "$CREATE_RESULT" | jq -r '.result.id')
        CREATED_EPICS+=("$VERTICAL|$NEW_NAME|$NEW_EPIC_ID")
        echo "✅ Created: $NEW_NAME ($NEW_EPIC_ID)"
    else
        FAILED_EPICS+=("$VERTICAL|$NEW_NAME")
        echo "❌ Failed to create epic for $VERTICAL"
        echo "   Error: $CREATE_RESULT"
    fi
done

# Summary
echo ""
echo "========================================"
echo "SUMMARY"
echo "========================================"
echo "Total epics to create: ${#VERTICALS[@]}"
echo "Successfully created: ${#CREATED_EPICS[@]}"
echo "Failed: ${#FAILED_EPICS[@]}"
echo ""

if [ ${#CREATED_EPICS[@]} -gt 0 ]; then
    echo "✅ Successfully Created Epics:"
    for epic in "${CREATED_EPICS[@]}"; do
        IFS='|' read -r VERTICAL NAME EPIC_ID <<< "$epic"
        echo "  [$VERTICAL] $NAME"
        echo "      → https://gus.lightning.force.com/lightning/r/ADM_Epic__c/$EPIC_ID/view"
    done
fi

if [ ${#FAILED_EPICS[@]} -gt 0 ]; then
    echo ""
    echo "❌ Failed Epics:"
    for epic in "${FAILED_EPICS[@]}"; do
        IFS='|' read -r VERTICAL NAME <<< "$epic"
        echo "  [$VERTICAL] $NAME"
    done
fi

echo ""
echo "========================================"
