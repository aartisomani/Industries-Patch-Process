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

# Create associative arrays for approved status
declare -A APPROVED_MAP
while read -r target_id; do
    APPROVED_MAP["$target_id"]=true
done < <(echo "$APPROVAL_RESULTS" | jq -r '.result.records[].TargetObjectId')

echo ""
echo "========================================"
echo "CAB APPROVAL STATUS"
echo "========================================"

# Analyze each CAB request
declare -A VERTICALS_TO_CREATE
declare -A PENDING_REQUESTS
declare -A NOT_YET_REQUESTS

while read -r cab_record; do
    CAB_ID=$(echo "$cab_record" | jq -r '.Id')
    CAB_NAME=$(echo "$cab_record" | jq -r '.Name')
    SCHEDULED_BUILD=$(echo "$cab_record" | jq -r '.Scheduled_Build_Ref__c')
    CLOUD_HEAD=$(echo "$cab_record" | jq -r '.Cloud_Head_Approval__c')

    # Extract vertical from Scheduled_Build_Ref__c (e.g., "Industries.CME 260.10" -> "CME")
    VERTICAL=$(echo "$SCHEDULED_BUILD" | sed -E 's/Industries\.([A-Z-]+).*/\1/')

    # Check if approved
    if [ "${APPROVED_MAP[$CAB_ID]}" = "true" ]; then
        echo "✅ $CAB_NAME ($VERTICAL): CAB Final Approval APPROVED"
        VERTICALS_TO_CREATE["$VERTICAL"]=true
    else
        # Not approved - check Cloud Head status
        if [ "$CLOUD_HEAD" = "true" ]; then
            echo "⏳ $CAB_NAME ($VERTICAL): Pending for you (Cloud Head approved)"
            PENDING_REQUESTS["$VERTICAL"]="${PENDING_REQUESTS[$VERTICAL]}$CAB_NAME "
        else
            echo "⏸️  $CAB_NAME ($VERTICAL): Not yet come for you (Cloud Head not approved)"
            NOT_YET_REQUESTS["$VERTICAL"]="${NOT_YET_REQUESTS[$VERTICAL]}$CAB_NAME "
        fi
    fi
done < <(echo "$CAB_RESULTS" | jq -c '.result.records[]')

echo ""
echo "========================================"
echo "STEP 4: CREATE RELEASE PROCESS"
echo "========================================"

if [ ${#VERTICALS_TO_CREATE[@]} -eq 0 ]; then
    echo "No verticals require release creation (none approved yet)"
    echo ""

    # Show pending status
    if [ ${#PENDING_REQUESTS[@]} -gt 0 ]; then
        echo "⏳ Pending for you:"
        for vertical in "${!PENDING_REQUESTS[@]}"; do
            echo "  $vertical: ${PENDING_REQUESTS[$vertical]}"
        done
    fi

    if [ ${#NOT_YET_REQUESTS[@]} -gt 0 ]; then
        echo "⏸️  Not yet come for you:"
        for vertical in "${!NOT_YET_REQUESTS[@]}"; do
            echo "  $vertical: ${NOT_YET_REQUESTS[$vertical]}"
        done
    fi

    exit 0
fi

echo "Verticals with CAB approval: ${!VERTICALS_TO_CREATE[@]}"
echo ""

# Check if releases already exist before creating
for vertical in "${!VERTICALS_TO_CREATE[@]}"; do
    echo "Checking if release exists for $vertical $VERSION..."

    # Check if patch work item exists
    EXISTING_WI=$(sf data query --target-org gus --query "SELECT Id, Name FROM ADM_Work__c WHERE Subject__c LIKE '%Patch $vertical $VERSION %' LIMIT 1" --json)
    WI_COUNT=$(echo "$EXISTING_WI" | jq '.result.totalSize')

    if [ "$WI_COUNT" -gt 0 ]; then
        WI_NAME=$(echo "$EXISTING_WI" | jq -r '.result.records[0].Name')
        echo "  ℹ️  Release already exists for $vertical $VERSION (Work Item: $WI_NAME)"
        echo "  ⏩ Skipping creation"
        unset VERTICALS_TO_CREATE["$vertical"]
    else
        echo "  ✨ No existing release found - will create"
    fi
    echo ""
done

# Create releases for remaining verticals
if [ ${#VERTICALS_TO_CREATE[@]} -eq 0 ]; then
    echo "All verticals already have releases created. No action needed."
    exit 0
fi

echo "========================================"
echo "CREATING RELEASES FOR: ${!VERTICALS_TO_CREATE[@]}"
echo "========================================"
echo ""

for vertical in "${!VERTICALS_TO_CREATE[@]}"; do
    echo "========================================"
    echo "Creating release for $vertical $VERSION"
    echo "========================================"

    # Run create-release.sh for this vertical
    echo "y" | "$SCRIPT_DIR/create-release.sh" "$vertical" "$VERSION" "Patch"

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
