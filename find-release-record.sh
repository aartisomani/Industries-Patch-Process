#!/bin/bash
# ============================================================
# FIND-RELEASE-RECORD - Look up the GUS Release record for a version
#
# Usage: ./find-release-record.sh <VERSION> [VERTICAL]
#
# Searches ADM_Release__c by name pattern. Returns Release record ID + Name.
# Used by deploy-patch.sh to locate the Release that Jenkins created.
#
# Examples:
#   ./find-release-record.sh 262.8           → finds any record with 262.8 + Patch
#   ./find-release-record.sh 262.8 CME       → filters to CME-named record
# ============================================================

VERSION="$1"
VERTICAL="$2"

if [ -z "$VERSION" ]; then
    echo "❌ Missing version. Usage: $0 <VERSION> [VERTICAL]"
    exit 1
fi

if [ -n "$VERTICAL" ]; then
    NAME_PATTERN="%${VERTICAL}%${VERSION}%Patch%"
else
    NAME_PATTERN="%${VERSION}%Patch%"
fi

QUERY="SELECT Id, Name, Status__c, Release_Type__c, Release_Date__c, Application__r.Name FROM ADM_Release__c WHERE Name LIKE '${NAME_PATTERN}' AND Application__r.Name = 'Industries' ORDER BY CreatedDate DESC LIMIT 5"

echo "🔍 Searching for Release records matching: $NAME_PATTERN"
echo ""

RESULT=$(sf data query --target-org gus --query "$QUERY" --json 2>&1)
COUNT=$(echo "$RESULT" | jq -r '.result.totalSize // 0')

if [ "$COUNT" = "0" ]; then
    echo "❌ No Release record found for version $VERSION"
    echo ""
    echo "   The Jenkins job may not have created the Release yet."
    echo "   Check: https://gus.lightning.force.com/lightning/o/ADM_Release__c/list"
    exit 1
fi

echo "Found $COUNT matching record(s):"
echo ""
echo "$RESULT" | jq -r '.result.records[] | "  \(.Id) | \(.Name) | Status: \(.Status__c // "N/A") | Date: \(.Release_Date__c // "N/A")"'
echo ""

# If exactly one, return it
if [ "$COUNT" = "1" ]; then
    RELEASE_ID=$(echo "$RESULT" | jq -r '.result.records[0].Id')
    RELEASE_NAME=$(echo "$RESULT" | jq -r '.result.records[0].Name')
    echo "✅ Single match — Release ID: $RELEASE_ID"
    echo "   URL: https://gus.lightning.force.com/lightning/r/ADM_Release__c/${RELEASE_ID}/view"
    # Print the ID on its own line at the very end so callers can capture it
    echo "RELEASE_ID=$RELEASE_ID"
    exit 0
fi

echo "⚠️  Multiple matches — please specify the correct Release ID manually"
exit 0
