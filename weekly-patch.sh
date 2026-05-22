#!/bin/bash

# CAB Approval Check and Auto-Create Release Script
# Usage: ./cab-approval-check-and-create.sh <version>
# Example: ./cab-approval-check-and-create.sh 260.10

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 260.10"
    exit 1
fi

VERSION="$1"
SCRIPT_DIR="$(dirname "$0")"

echo "========================================"
echo "CAB APPROVAL CHECK & AUTO-CREATE RELEASE"
echo "========================================"
echo "Version: $VERSION"
echo "========================================"
echo ""

# Step 1-2: Query CAB Patch Candidates with filters
echo "Step 1-2: Querying CAB Patch Candidates..."
CAB_QUERY="SELECT Id, Name, Stage__c, Scheduled_Build_Ref__c, Cloud_Architect_Approval__c, Cloud_Lead_Approval__c, Cloud_Head_Approval__c FROM CAB_Patch_Candidate__c WHERE Scheduled_Build_Ref__c LIKE '%${VERSION}%' AND (Scheduled_Build_Ref__c LIKE '%Industries.CME%' OR Scheduled_Build_Ref__c LIKE '%Industries.INS%' OR Scheduled_Build_Ref__c LIKE '%Industries.PS%' OR Scheduled_Build_Ref__c LIKE '%Industries.OS%' OR Scheduled_Build_Ref__c LIKE '%Industries.INS%FSC%') AND Stage__c IN ('Awaiting Approval', 'Pending Release', 'Close')"

CAB_RESULTS=$(sf data query --target-org gus --query "$CAB_QUERY" --json)
CAB_COUNT=$(echo "$CAB_RESULTS" | jq '.result.totalSize')

echo "Found $CAB_COUNT CAB Patch Candidate(s)"
echo ""

if [ "$CAB_COUNT" -eq 0 ]; then
    echo "No CAB Patch Candidates found for version $VERSION with Industries filters"
    exit 0
fi

# Step 3: Check CAB Final Approval for each request
echo "Step 3: Checking CAB Final Approval status..."
CAB_IDS=$(echo "$CAB_RESULTS" | jq -r '.result.records[].Id' | tr '\n' ',' | sed 's/,$//')

APPROVAL_QUERY="SELECT Id, TargetObjectId, Status FROM ProcessInstance WHERE TargetObjectId IN ($CAB_IDS) AND Status = 'Approved'"
APPROVAL_RESULTS=$(sf data query --target-org gus --query "$APPROVAL_QUERY" --json)

# Build approved IDs list (bash 3.2 compatible - no associative arrays)
APPROVED_IDS=$(echo "$APPROVAL_RESULTS" | jq -r '.result.records[].TargetObjectId' | tr '\n' ' ')

echo ""
echo "========================================"
echo "CAB APPROVAL STATUS"
echo "========================================"

# Analyze each CAB request (bash 3.2 compatible - use space-separated strings)
VERTICALS_TO_CREATE=""
PENDING_VERTICALS=""
NOT_YET_VERTICALS=""
PENDING_DETAILS=""
NOT_YET_DETAILS=""

while read -r cab_record; do
    CAB_ID=$(echo "$cab_record" | jq -r '.Id')
    CAB_NAME=$(echo "$cab_record" | jq -r '.Name')
    SCHEDULED_BUILD=$(echo "$cab_record" | jq -r '.Scheduled_Build_Ref__c')
    CLOUD_HEAD=$(echo "$cab_record" | jq -r '.Cloud_Head_Approval__c')

    # Extract vertical from Scheduled_Build_Ref__c (e.g., "Industries.CME 260.10" -> "CME")
    VERTICAL=$(echo "$SCHEDULED_BUILD" | sed -E 's/Industries\.([A-Z-]+).*/\1/')

    # Check if approved (grep for ID in approved list)
    if echo "$APPROVED_IDS" | grep -qw "$CAB_ID"; then
        echo "✅ $CAB_NAME ($VERTICAL): CAB Final Approval APPROVED"
        if ! echo "$VERTICALS_TO_CREATE" | grep -qw "$VERTICAL"; then
            VERTICALS_TO_CREATE="$VERTICALS_TO_CREATE $VERTICAL"
        fi
    else
        # Not approved - check Cloud Head status
        if [ "$CLOUD_HEAD" = "true" ]; then
            echo "⏳ $CAB_NAME ($VERTICAL): Pending for you (Cloud Head approved)"
            PENDING_DETAILS="$PENDING_DETAILS\n  $VERTICAL: $CAB_NAME"
            if ! echo "$PENDING_VERTICALS" | grep -qw "$VERTICAL"; then
                PENDING_VERTICALS="$PENDING_VERTICALS $VERTICAL"
            fi
        else
            echo "⏸️  $CAB_NAME ($VERTICAL): Not yet come for you (Cloud Head not approved)"
            NOT_YET_DETAILS="$NOT_YET_DETAILS\n  $VERTICAL: $CAB_NAME"
            if ! echo "$NOT_YET_VERTICALS" | grep -qw "$VERTICAL"; then
                NOT_YET_VERTICALS="$NOT_YET_VERTICALS $VERTICAL"
            fi
        fi
    fi
done < <(echo "$CAB_RESULTS" | jq -c '.result.records[]')

echo ""
echo "========================================"
echo "STEP 4: CREATE RELEASE PROCESS"
echo "========================================"

VERTICALS_TO_CREATE=$(echo "$VERTICALS_TO_CREATE" | xargs)  # trim whitespace

if [ -z "$VERTICALS_TO_CREATE" ]; then
    echo "No verticals require release creation (none approved yet)"
    echo ""

    # Show pending status
    if [ -n "$PENDING_DETAILS" ]; then
        echo "⏳ Pending for you:"
        echo -e "$PENDING_DETAILS"
    fi

    if [ -n "$NOT_YET_DETAILS" ]; then
        echo "⏸️  Not yet come for you:"
        echo -e "$NOT_YET_DETAILS"
    fi

    exit 0
fi

echo "Verticals with CAB approval: $VERTICALS_TO_CREATE"
echo ""

# Check if releases already exist before creating
FINAL_VERTICALS=""
for vertical in $VERTICALS_TO_CREATE; do
    echo "Checking if release exists for $vertical $VERSION..."

    # Check if patch work item exists
    EXISTING_WI=$(sf data query --target-org gus --query "SELECT Id, Name FROM ADM_Work__c WHERE Subject__c LIKE '%Patch $vertical $VERSION %' LIMIT 1" --json)
    WI_COUNT=$(echo "$EXISTING_WI" | jq '.result.totalSize')

    if [ "$WI_COUNT" -gt 0 ]; then
        WI_NAME=$(echo "$EXISTING_WI" | jq -r '.result.records[0].Name')
        echo "  ℹ️  Release already exists for $vertical $VERSION (Work Item: $WI_NAME)"
        echo "  ⏩ Skipping creation"
    else
        echo "  ✨ No existing release found - will create"
        FINAL_VERTICALS="$FINAL_VERTICALS $vertical"
    fi
    echo ""
done

FINAL_VERTICALS=$(echo "$FINAL_VERTICALS" | xargs)  # trim whitespace

# Create releases for remaining verticals
if [ -z "$FINAL_VERTICALS" ]; then
    echo "All verticals already have releases created. No action needed."
    exit 0
fi

echo "========================================"
echo "CREATING RELEASES FOR: $FINAL_VERTICALS"
echo "========================================"
echo ""

for vertical in $FINAL_VERTICALS; do
    echo "========================================"
    echo "Creating release for $vertical $VERSION"
    echo "========================================"

    # Run create-release.sh for this vertical
    "$SCRIPT_DIR/create-release.sh" "$vertical" "$VERSION" "Patch"

    if [ $? -eq 0 ]; then
        echo "✅ Release created successfully for $vertical $VERSION"
    else
        echo "❌ Failed to create release for $vertical $VERSION"
    fi

    echo ""
done

echo "========================================"
echo "COMPLETE"
echo "========================================"
