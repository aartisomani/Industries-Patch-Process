#!/bin/bash
# ============================================================
# ADD-SIGNOFFS - Add per-vertical sign-offs to the Release record
#
# Stateless: queries GUS directly for the Release record by version.
# Does NOT read or write patch-state.json.
#
# Usage: ./add-signoffs.sh <VERSION> [VERTICAL]
#
# Reads:
#   - signoff-config.json for which Application Approvers to add per vertical
#
# Creates one ADM_Signoff__c record per approver, linked to the Release.
#
# If VERTICAL is omitted, adds sign-offs for all 4 verticals + shared.
# ============================================================

set -e

VERSION="$1"
SINGLE_VERTICAL="$2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$VERSION" ]; then
    echo "❌ Missing version. Usage: $0 <VERSION> [VERTICAL]"
    exit 1
fi

SIGNOFF_CONFIG="$SCRIPT_DIR/signoff-config.json"

# Query GUS for the Release record by version (stateless lookup)
echo "🔍 Looking up Release record for $VERSION in GUS..."
QUERY="SELECT Id, Name FROM ADM_Release__c WHERE Name LIKE '%${VERSION}%Patch%' AND Application__r.Name = 'Industries' ORDER BY CreatedDate DESC LIMIT 1"
RELEASE_DATA=$(sf data query --target-org gus --query "$QUERY" --json 2>&1)
RELEASE_ID=$(echo "$RELEASE_DATA" | jq -r '.result.records[0].Id // "null"')
RELEASE_NAME=$(echo "$RELEASE_DATA" | jq -r '.result.records[0].Name // ""')

if [ "$RELEASE_ID" = "null" ]; then
    echo "❌ No Release record found for version $VERSION in GUS"
    echo "   The Jenkins job may not have created it yet."
    exit 1
fi

echo "✅ Found Release: $RELEASE_NAME ($RELEASE_ID)"
echo "========================================"

# Determine which verticals to process
if [ -n "$SINGLE_VERTICAL" ]; then
    VERTICALS=("$SINGLE_VERTICAL")
else
    VERTICALS=("CME" "INS" "OS" "INS-FSC")
fi

CREATED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0

# Process per-vertical approvers
for VERTICAL in "${VERTICALS[@]}"; do
    echo ""
    echo "── $VERTICAL ──"

    APPROVERS=$(jq -r ".verticals.\"$VERTICAL\".approvers[]?" "$SIGNOFF_CONFIG" 2>/dev/null)

    if [ -z "$APPROVERS" ]; then
        echo "  ⚠️  No approvers configured for $VERTICAL in signoff-config.json — skipping"
        continue
    fi

    while IFS= read -r APPROVER_ID; do
        if [ -z "$APPROVER_ID" ]; then continue; fi

        # Look up the User behind this Application Approver record (so we can set Approver__c too)
        APPROVER_DATA=$(sf data query --target-org gus --query \
            "SELECT Id, Name, Approver__c, Approver__r.Name FROM ADM_Application_Approver__c WHERE Id = '$APPROVER_ID' LIMIT 1" --json 2>/dev/null)
        APPROVER_NAME=$(echo "$APPROVER_DATA" | jq -r '.result.records[0].Approver__r.Name // "Unknown"')
        APPROVER_USER_ID=$(echo "$APPROVER_DATA" | jq -r '.result.records[0].Approver__c // "null"')
        APPROVER_AA_NAME=$(echo "$APPROVER_DATA" | jq -r '.result.records[0].Name // "?"')

        # Check if a sign-off already exists for this Release + Approver
        EXISTING=$(sf data query --target-org gus --query \
            "SELECT Id FROM ADM_Signoff__c WHERE Release__c = '$RELEASE_ID' AND Release_Approver__c = '$APPROVER_ID' LIMIT 1" --json 2>/dev/null)
        EXISTING_ID=$(echo "$EXISTING" | jq -r '.result.records[0].Id // "null"')

        if [ "$EXISTING_ID" != "null" ]; then
            echo "  ⏩ Already exists for $APPROVER_AA_NAME ($APPROVER_NAME) → $EXISTING_ID"
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            continue
        fi

        # Build the create command
        VALUES="Release__c='$RELEASE_ID' Release_Approver__c='$APPROVER_ID' Approval_Status__c='Pending' checked__c=false Approval_Comments_Available__c=false Auto_Approved__c=false"
        if [ "$APPROVER_USER_ID" != "null" ]; then
            VALUES="$VALUES Approver__c='$APPROVER_USER_ID'"
        fi

        CREATE_RESULT=$(sf data create record --target-org gus --sobject ADM_Signoff__c --values "$VALUES" --json 2>&1)
        NEW_ID=$(echo "$CREATE_RESULT" | jq -r '.result.id // "null"')

        if [ "$NEW_ID" != "null" ]; then
            echo "  ✅ Created sign-off for $APPROVER_AA_NAME ($APPROVER_NAME) → $NEW_ID"
            CREATED_COUNT=$((CREATED_COUNT + 1))
        else
            ERROR=$(echo "$CREATE_RESULT" | jq -r '.message // .stack // "unknown"' | head -c 200)
            echo "  ❌ Failed for $APPROVER_AA_NAME: $ERROR"
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    done <<< "$APPROVERS"
done

# Process shared approvers (added once, regardless of vertical)
if [ -z "$SINGLE_VERTICAL" ]; then
    SHARED=$(jq -r '._shared_approvers.approvers[]?' "$SIGNOFF_CONFIG" 2>/dev/null)
    if [ -n "$SHARED" ]; then
        echo ""
        echo "── Shared approvers ──"
        while IFS= read -r APPROVER_ID; do
            if [ -z "$APPROVER_ID" ]; then continue; fi
            APPROVER_DATA=$(sf data query --target-org gus --query \
                "SELECT Id, Name, Approver__c, Approver__r.Name FROM ADM_Application_Approver__c WHERE Id = '$APPROVER_ID' LIMIT 1" --json 2>/dev/null)
            APPROVER_NAME=$(echo "$APPROVER_DATA" | jq -r '.result.records[0].Approver__r.Name // "Unknown"')
            APPROVER_USER_ID=$(echo "$APPROVER_DATA" | jq -r '.result.records[0].Approver__c // "null"')
            APPROVER_AA_NAME=$(echo "$APPROVER_DATA" | jq -r '.result.records[0].Name // "?"')

            EXISTING=$(sf data query --target-org gus --query \
                "SELECT Id FROM ADM_Signoff__c WHERE Release__c = '$RELEASE_ID' AND Release_Approver__c = '$APPROVER_ID' LIMIT 1" --json 2>/dev/null)
            EXISTING_ID=$(echo "$EXISTING" | jq -r '.result.records[0].Id // "null"')
            if [ "$EXISTING_ID" != "null" ]; then
                echo "  ⏩ Already exists for $APPROVER_AA_NAME → $EXISTING_ID"
                SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                continue
            fi

            VALUES="Release__c='$RELEASE_ID' Release_Approver__c='$APPROVER_ID' Approval_Status__c='Pending' checked__c=false Approval_Comments_Available__c=false Auto_Approved__c=false"
            if [ "$APPROVER_USER_ID" != "null" ]; then
                VALUES="$VALUES Approver__c='$APPROVER_USER_ID'"
            fi
            CREATE_RESULT=$(sf data create record --target-org gus --sobject ADM_Signoff__c --values "$VALUES" --json 2>&1)
            NEW_ID=$(echo "$CREATE_RESULT" | jq -r '.result.id // "null"')
            if [ "$NEW_ID" != "null" ]; then
                echo "  ✅ Created sign-off for $APPROVER_AA_NAME ($APPROVER_NAME) → $NEW_ID"
                CREATED_COUNT=$((CREATED_COUNT + 1))
            else
                echo "  ❌ Failed for $APPROVER_AA_NAME"
                FAILED_COUNT=$((FAILED_COUNT + 1))
            fi
        done <<< "$SHARED"
    fi
fi

echo ""
echo "========================================"
echo "Summary: $CREATED_COUNT created, $SKIPPED_COUNT skipped, $FAILED_COUNT failed"
echo "Release: https://gus.lightning.force.com/lightning/r/ADM_Release__c/${RELEASE_ID}/view"

if [ "$FAILED_COUNT" -gt 0 ]; then
    exit 1
fi
