#!/bin/bash
# ============================================================================
# link-cab-children.sh
#
# Idempotent linker — for each <vertical> + <version>, finds the RM WI in GUS
# and attaches every CAB Patch Candidate's Work__c as a child of it
# (ADM_Parent_Work__c).
#
# Safe to re-run: existing (parent, child) pairs are detected and skipped, so
# no duplicate parent-work records are created. If the RM WI for a vertical is
# missing from GUS, that vertical is skipped with a warning — never silently
# creates orphan links.
#
# Usage:
#   ./link-cab-children.sh <verticals-slash-list> <version>
#
# Example:
#   ./link-cab-children.sh CME/INS/OS 262.8
#
# Called from weekly-patch.sh after RM WIs are created/verified, but the
# script is also safe to invoke standalone for manual repair.
# ============================================================================

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <verticals-slash-list> <version>"
    echo "Example: $0 CME/INS/OS 262.8"
    exit 1
fi

VERTICALS_INPUT="$1"
VERSION="$2"

IFS='/' read -ra VERTICALS <<< "$VERTICALS_INPUT"

echo "========================================"
echo "LINKING CAB PATCH CANDIDATES → RM WORK ITEMS"
echo "Verticals: ${VERTICALS[*]}"
echo "Version:   $VERSION"
echo "========================================"

# ── Helpers ──────────────────────────────────────────────────────────────────

_gus_query() {
    # _gus_query <soql> — runs sf data query --json, fails loud on error.
    local q="$1"
    local raw
    raw=$(sf data query --target-org gus --query "$q" --json 2>&1) || {
        echo "❌ SOQL query failed:" >&2
        echo "   Query: $q"   >&2
        echo "   Output: $raw" >&2
        exit 1
    }
    echo "$raw"
}

cab_filter_for() {
    case "$1" in
        CME)     echo "Industries.CME" ;;
        INS)     echo "Industries.INS" ;;
        OS)      echo "Industries.OS"  ;;
        INS-FSC) echo "Industries.INS" ;;
        *)       echo "" ;;
    esac
}

# ── Main loop ────────────────────────────────────────────────────────────────

GLOBAL_NEW=0
GLOBAL_SKIP=0
GLOBAL_FAIL=0

for VERTICAL in "${VERTICALS[@]}"; do
    echo ""
    echo "── $VERTICAL ──────────────────────────────"

    # 1) Find the RM WI for this vertical+version. Strict subject match,
    #    excludes Closed (so [DUPLICATE] entries can't be picked up).
    RM_Q="SELECT Id, Name FROM ADM_Work__c \
WHERE Subject__c LIKE '[Vlocity-${VERTICAL}] Patch ${VERTICAL} ${VERSION} %' \
  AND Status__c != 'Closed' \
ORDER BY CreatedDate DESC LIMIT 1"

    RM_RAW=$(_gus_query "$RM_Q")
    RM_TOTAL=$(echo "$RM_RAW" | jq '.result.totalSize')

    if [ "$RM_TOTAL" -eq 0 ]; then
        echo "  ⚠️  No RM WI in GUS for $VERTICAL $VERSION — skipping (nothing to link to)."
        continue
    fi

    RM_WI_ID=$(echo "$RM_RAW" | jq -r '.result.records[0].Id')
    RM_WI_NM=$(echo "$RM_RAW" | jq -r '.result.records[0].Name')
    echo "  RM WI: $RM_WI_NM ($RM_WI_ID)"

    # 2) Build the CAB-candidate query for this vertical.
    if [ "$VERTICAL" == "INS-FSC" ]; then
        CAB_Q="SELECT Id, Name, Work__c FROM CAB_Patch_Candidate__c \
WHERE Scheduled_Build_Ref__c LIKE '%${VERSION}%' \
  AND Scheduled_Build_Ref__c LIKE '%Industries.INS%FSC%' \
  AND Stage__c IN ('Awaiting Approval', 'Pending Release', 'Close') \
  AND Work__c != null"
    else
        FILTER=$(cab_filter_for "$VERTICAL")
        CAB_Q="SELECT Id, Name, Work__c FROM CAB_Patch_Candidate__c \
WHERE Scheduled_Build_Ref__c LIKE '%${VERSION}%' \
  AND Scheduled_Build_Ref__c LIKE '%${FILTER}%' \
  AND (NOT Scheduled_Build_Ref__c LIKE '%FSC%') \
  AND Stage__c IN ('Awaiting Approval', 'Pending Release', 'Close') \
  AND Work__c != null"
    fi

    CAB_RAW=$(_gus_query "$CAB_Q")
    CAB_TOTAL=$(echo "$CAB_RAW" | jq '.result.totalSize')

    if [ "$CAB_TOTAL" -eq 0 ]; then
        echo "  ⚠️  No CAB Patch Candidates found — nothing to link."
        continue
    fi
    echo "  Found $CAB_TOTAL CAB candidate(s)."

    NEW=0
    SKIP=0
    FAIL=0

    while read -r row; do
        CAB_NAME=$(echo "$row" | jq -r '.Name')
        CHILD_ID=$(echo "$row" | jq -r '.Work__c')

        # Get child WI display name (best-effort).
        CHILD_DATA=$(sf data query --target-org gus --query \
            "SELECT Name FROM ADM_Work__c WHERE Id = '$CHILD_ID'" --json 2>/dev/null || echo '{}')
        CHILD_NUM=$(echo "$CHILD_DATA" | jq -r '.result.records[0].Name // "unknown"')

        # 3a) Pre-check: does this (parent, child) link already exist?
        EXIST_Q="SELECT Id FROM ADM_Parent_Work__c \
WHERE Parent_Work__c = '$RM_WI_ID' AND Child_Work__c = '$CHILD_ID' LIMIT 1"
        EXIST_RAW=$(_gus_query "$EXIST_Q")
        EXIST_TOTAL=$(echo "$EXIST_RAW" | jq '.result.totalSize')

        if [ "$EXIST_TOTAL" -gt 0 ]; then
            echo "  ⏩ Already linked: $CHILD_NUM ($CAB_NAME)"
            SKIP=$((SKIP + 1))
            continue
        fi

        # 3b) Create the link, with belt-and-braces dup detection on the
        # response (in case of races between our pre-check and the insert).
        RESULT=$(sf data create record \
            --target-org gus \
            --sobject ADM_Parent_Work__c \
            --values "Parent_Work__c='$RM_WI_ID' Child_Work__c='$CHILD_ID'" \
            --json 2>/dev/null || true)

        STATUS=$(echo "$RESULT" | jq -r '.status // "1"')
        if [ "$STATUS" == "0" ]; then
            echo "  ✅ Linked: $CHILD_NUM ($CAB_NAME)"
            NEW=$((NEW + 1))
        else
            ERROR_MSG=$(echo "$RESULT" | jq -r '.message // "unknown error"')
            if echo "$ERROR_MSG" | grep -qi "duplicate\|already exists"; then
                echo "  ⏩ Already linked (race): $CHILD_NUM ($CAB_NAME)"
                SKIP=$((SKIP + 1))
            else
                echo "  ❌ Failed to link $CHILD_NUM: $ERROR_MSG"
                FAIL=$((FAIL + 1))
            fi
        fi
    done < <(echo "$CAB_RAW" | jq -c '.result.records[]')

    echo "  [$VERTICAL] Linked $NEW new, skipped $SKIP existing, $FAIL failed."
    GLOBAL_NEW=$((GLOBAL_NEW + NEW))
    GLOBAL_SKIP=$((GLOBAL_SKIP + SKIP))
    GLOBAL_FAIL=$((GLOBAL_FAIL + FAIL))
done

echo ""
echo "========================================"
echo "✅ CHILD-RECORD LINK STEP COMPLETE"
echo "   New: $GLOBAL_NEW   Already linked: $GLOBAL_SKIP   Failed: $GLOBAL_FAIL"
echo "========================================"

[ "$GLOBAL_FAIL" -gt 0 ] && exit 1 || exit 0
