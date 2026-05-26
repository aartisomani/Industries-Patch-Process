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
CAB_IDS=$(echo "$CAB_RESULTS" | jq -r '.result.records[].Id' | sed "s/.*/'&'/" | tr '\n' ',' | sed 's/,$//')

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

VERTICALS_TO_CREATE=$(echo "$VERTICALS_TO_CREATE" | xargs)  # trim whitespace
echo "Verticals with CAB approval: $VERTICALS_TO_CREATE"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Sync release schedule once for the whole batch (idempotent, non-fatal).
# ─────────────────────────────────────────────────────────────────────────────
python3 "$SCRIPT_DIR/sync-schedule.py" || echo "⚠️  schedule sync skipped (non-fatal)"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Helpers — query GUS for whether a given component already exists for a
# (vertical, version). Echoes "yes" or "no" so callers can branch on it.
# Single source of truth = GUS state, never script flow control.
#
# Fail-loud guard: any SOQL/jq failure aborts the whole script. We MUST NOT
# silently treat "query failed" as "vertical missing" — that's exactly the
# bug that caused duplicate WI creation on 2026-05-26.
#
# Subject-line conventions used:
#   • Epic         : Industries.<V> <VER> ... Patch
#   • RM WI        : [Vlocity-<V>] Patch <V> <VER> (...)
#   • Package WI   : [Vlocity-<V>] Package creation for version <V> <VER>...
#     ([DUPLICATE] / Closed records are ignored via Status filter.)
# ─────────────────────────────────────────────────────────────────────────────

# _gus_count <soql>  — runs the query, prints totalSize. Aborts on any error.
_gus_count() {
    local q="$1"
    local raw
    raw=$(sf data query --target-org gus --query "$q" --json 2>&1) || {
        echo "❌ SOQL query failed (sf data query exit non-zero):" >&2
        echo "   Query: $q" >&2
        echo "   Output: $raw" >&2
        exit 1
    }
    local n
    n=$(echo "$raw" | jq -r '.result.totalSize // "ERR"')
    if [ "$n" = "ERR" ] || ! [[ "$n" =~ ^[0-9]+$ ]]; then
        echo "❌ SOQL query did not return totalSize:" >&2
        echo "   Query: $q" >&2
        echo "   Output: $raw" >&2
        exit 1
    fi
    echo "$n"
}

has_epic() {
    local vertical="$1"
    local q="SELECT Id FROM ADM_Epic__c WHERE Name LIKE 'Industries.${vertical} ${VERSION}%Patch%' LIMIT 1"
    local n; n=$(_gus_count "$q")
    [ "$n" -gt 0 ] && echo "yes" || echo "no"
}

has_rm_wi() {
    local vertical="$1"
    # Match the exact RM WI subject pattern. Excludes Closed records (so
    # tagged [DUPLICATE] entries don't make us think a vertical is done).
    local q="SELECT Id FROM ADM_Work__c WHERE Subject__c LIKE '[Vlocity-${vertical}] Patch ${vertical} ${VERSION} %' AND Status__c != 'Closed' LIMIT 1"
    local n; n=$(_gus_count "$q")
    [ "$n" -gt 0 ] && echo "yes" || echo "no"
}

has_pkg_drop() {
    local vertical="$1"
    # Convention: subject is "[Vlocity-<V>] Package creation for version <V> <VER>"
    # (with optional " Monthly" suffix for monthly patches).
    local q="SELECT Id FROM ADM_Work__c WHERE Subject__c LIKE '[Vlocity-${vertical}] Package creation for version ${vertical} ${VERSION}%' AND Status__c != 'Closed' LIMIT 1"
    local n; n=$(_gus_count "$q")
    [ "$n" -gt 0 ] && echo "yes" || echo "no"
}

# Build a slash-delimited list of verticals from a space-delimited one.
to_slash_list() {
    echo "$1" | tr ' ' '/' | sed 's|^/||;s|/$||;s|//*|/|g'
}

# Pretty link for a Work record.
wi_link() { echo "https://gus.lightning.force.com/lightning/r/ADM_Work__c/$1/view"; }
ep_link() { echo "https://gus.lightning.force.com/lightning/r/ADM_Epic__c/$1/view"; }

# ─────────────────────────────────────────────────────────────────────────────
# Pre-flight per-component existence check. We compute one batch per step.
# ─────────────────────────────────────────────────────────────────────────────
echo "========================================"
echo "PRE-FLIGHT — current GUS state"
echo "========================================"

NEEDS_EPIC=""
NEEDS_WI=""
NEEDS_PD=""

for v in $VERTICALS_TO_CREATE; do
    e=$(has_epic     "$v")
    w=$(has_rm_wi    "$v")
    p=$(has_pkg_drop "$v")
    printf "  %-8s  Epic:%s  RM WI:%s  Package WI:%s\n" "$v" "$e" "$w" "$p"
    [ "$e" = "no" ] && NEEDS_EPIC="$NEEDS_EPIC $v"
    [ "$w" = "no" ] && NEEDS_WI="$NEEDS_WI $v"
    [ "$p" = "no" ] && NEEDS_PD="$NEEDS_PD $v"
done

NEEDS_EPIC=$(echo "$NEEDS_EPIC" | xargs)
NEEDS_WI=$(echo "$NEEDS_WI"     | xargs)
NEEDS_PD=$(echo "$NEEDS_PD"     | xargs)

echo ""
echo "Plan:"
echo "  Need Epic        : ${NEEDS_EPIC:-(none)}"
echo "  Need RM WI       : ${NEEDS_WI:-(none)}"
echo "  Need Package WI: ${NEEDS_PD:-(none)}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# run_step <step-name> <verticals> <retry-fn>
#   verticals : space-delimited list of verticals that still need this step
#   retry-fn  : function that takes a slash-list and runs the helper
# After running once, we re-query GUS and retry once for any vertical that's
# still missing. Whatever is missing after retry is reported and excluded
# from later steps (Slack, etc.) for that vertical.
# ─────────────────────────────────────────────────────────────────────────────
run_step() {
    local step_name="$1"   # "epic" / "rm_wi" / "pkg_drop"
    local todo="$2"        # space-delimited
    local label="$3"

    [ -z "$todo" ] && { echo "⏩ $label — nothing to do."; echo ""; return 0; }

    echo "========================================"
    echo "STEP — $label"
    echo "Targets: $todo"
    echo "========================================"

    local slash_list
    slash_list=$(to_slash_list "$todo")

    case "$step_name" in
        epic)     yes | "$SCRIPT_DIR/clone-epic-v3.sh"        "$slash_list" "$VERSION" "Patch" || true ;;
        rm_wi)    yes | "$SCRIPT_DIR/create-work-items.sh"    "$slash_list" "$VERSION" "Patch" || true ;;
        pkg_drop)        "$SCRIPT_DIR/create-package-drops.sh" --yes "$slash_list" "$VERSION" || true ;;
    esac

    # Re-verify and retry-once for any stragglers.
    local still_missing=""
    for v in $todo; do
        local present
        case "$step_name" in
            epic)     present=$(has_epic     "$v") ;;
            rm_wi)    present=$(has_rm_wi    "$v") ;;
            pkg_drop) present=$(has_pkg_drop "$v") ;;
        esac
        [ "$present" = "no" ] && still_missing="$still_missing $v"
    done
    still_missing=$(echo "$still_missing" | xargs)

    if [ -n "$still_missing" ]; then
        echo ""
        echo "🔁 Retrying $label for: $still_missing"
        local retry_slash
        retry_slash=$(to_slash_list "$still_missing")
        case "$step_name" in
            epic)     yes | "$SCRIPT_DIR/clone-epic-v3.sh"        "$retry_slash" "$VERSION" "Patch" || true ;;
            rm_wi)    yes | "$SCRIPT_DIR/create-work-items.sh"    "$retry_slash" "$VERSION" "Patch" || true ;;
            pkg_drop)        "$SCRIPT_DIR/create-package-drops.sh" --yes "$retry_slash" "$VERSION" || true ;;
        esac
    fi
    echo ""
}

# ── Step 1: Epics ────────────────────────────────────────────────────────────
run_step epic "$NEEDS_EPIC" "Create missing Epics"

# Re-verify epics; any vertical still without an epic CANNOT progress to RM WI
# or Package WI in this run. Drop them from later steps.
EPIC_OK=""
for v in $VERTICALS_TO_CREATE; do
    [ "$(has_epic "$v")" = "yes" ] && EPIC_OK="$EPIC_OK $v"
done
EPIC_OK=$(echo "$EPIC_OK" | xargs)

# Filter NEEDS_WI / NEEDS_PD to only verticals whose epic now exists.
NEEDS_WI=$(echo "$NEEDS_WI" | xargs -n1 2>/dev/null | while read -r v; do
    [ -z "$v" ] && continue
    echo " $EPIC_OK " | grep -q " $v " && echo "$v"
done | xargs)

NEEDS_PD_TENTATIVE=$(echo "$NEEDS_PD" | xargs -n1 2>/dev/null | while read -r v; do
    [ -z "$v" ] && continue
    echo " $EPIC_OK " | grep -q " $v " && echo "$v"
done | xargs)

# ── Step 2: RM Work Items ────────────────────────────────────────────────────
run_step rm_wi "$NEEDS_WI" "Create missing RM Work Items"

# A Package WI has no hard dependency on the RM WI in GUS, but we use the RM
# WI's existence as a sanity check that the vertical's Friday flow is sound.
WI_OK=""
for v in $VERTICALS_TO_CREATE; do
    [ "$(has_rm_wi "$v")" = "yes" ] && WI_OK="$WI_OK $v"
done
WI_OK=$(echo "$WI_OK" | xargs)

NEEDS_PD=$(echo "$NEEDS_PD_TENTATIVE" | xargs -n1 2>/dev/null | while read -r v; do
    [ -z "$v" ] && continue
    echo " $WI_OK " | grep -q " $v " && echo "$v"
done | xargs)

# ── Step 3: Package WI Work Items ──────────────────────────────────────────
run_step pkg_drop "$NEEDS_PD" "Create missing Package WI Work Items"

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Link CAB Patch Candidates as child work records under each RM WI.
# Idempotent — for verticals that already have child links it just reports
# "already linked" and moves on. For verticals whose RM WI didn't get created
# (failed earlier steps), the linker prints a warning and skips them. We only
# attempt this for verticals whose RM WI now exists.
# ─────────────────────────────────────────────────────────────────────────────
LINK_LIST=""
for v in $VERTICALS_TO_CREATE; do
    [ "$(has_rm_wi "$v")" = "yes" ] && LINK_LIST="$LINK_LIST $v"
done
LINK_LIST=$(echo "$LINK_LIST" | xargs)

if [ -n "$LINK_LIST" ]; then
    LINK_SLASH=$(to_slash_list "$LINK_LIST")
    echo ""
    echo "========================================"
    echo "STEP — Link CAB Patch Candidates as children"
    echo "Targets: $LINK_LIST"
    echo "========================================"
    "$SCRIPT_DIR/link-cab-children.sh" "$LINK_SLASH" "$VERSION" || \
        echo "⚠️  Some child-record links failed (see output above)."
    echo ""
fi

# ─────────────────────────────────────────────────────────────────────────────
# FINAL VERIFICATION — query GUS for every approved vertical and report.
# Exit 0 only if every vertical has all three artifacts.
# ─────────────────────────────────────────────────────────────────────────────
echo "========================================"
echo "FINAL VERIFICATION (GUS)"
echo "Version: $VERSION"
echo "========================================"

ALL_OK=true
COMPLETE_LIST=""
INCOMPLETE_LIST=""

for v in $VERTICALS_TO_CREATE; do
    EPIC_Q=$(sf data query --target-org gus --json --query \
        "SELECT Id, Name FROM ADM_Epic__c WHERE Name LIKE 'Industries.${v} ${VERSION}%Patch%' ORDER BY CreatedDate DESC LIMIT 1") || {
            echo "❌ SOQL failed for Epic verification ($v)" >&2; exit 1; }
    WI_Q=$(sf data query --target-org gus --json --query \
        "SELECT Id, Name, Subject__c FROM ADM_Work__c WHERE Subject__c LIKE '[Vlocity-${v}] Patch ${v} ${VERSION} %' AND Status__c != 'Closed' ORDER BY CreatedDate DESC LIMIT 1") || {
            echo "❌ SOQL failed for RM WI verification ($v)" >&2; exit 1; }
    PD_Q=$(sf data query --target-org gus --json --query \
        "SELECT Id, Name, Subject__c FROM ADM_Work__c WHERE Subject__c LIKE '[Vlocity-${v}] Package creation for version ${v} ${VERSION}%' AND Status__c != 'Closed' ORDER BY CreatedDate DESC LIMIT 1") || {
            echo "❌ SOQL failed for Package WI verification ($v)" >&2; exit 1; }

    EPIC_ID=$(echo "$EPIC_Q" | jq -r '.result.records[0].Id   // empty')
    EPIC_NM=$(echo "$EPIC_Q" | jq -r '.result.records[0].Name // empty')
    WI_ID=$(echo   "$WI_Q"   | jq -r '.result.records[0].Id   // empty')
    WI_NM=$(echo   "$WI_Q"   | jq -r '.result.records[0].Name // empty')
    PD_ID=$(echo   "$PD_Q"   | jq -r '.result.records[0].Id   // empty')
    PD_NM=$(echo   "$PD_Q"   | jq -r '.result.records[0].Name // empty')

    # Child-record count — only meaningful if RM WI exists.
    CHILD_COUNT=0
    EXPECTED_CHILDREN=0
    if [ -n "$WI_ID" ]; then
        CHILD_Q=$(sf data query --target-org gus --json --query \
            "SELECT Id FROM ADM_Parent_Work__c WHERE Parent_Work__c = '$WI_ID'") || {
                echo "❌ SOQL failed for child-record count ($v)" >&2; exit 1; }
        CHILD_COUNT=$(echo "$CHILD_Q" | jq '.result.totalSize')

        # Expected = CAB candidates for this vertical/version that have a
        # linked Work record.
        if [ "$v" = "INS-FSC" ]; then
            CAB_FILTER_Q="Scheduled_Build_Ref__c LIKE '%${VERSION}%' AND Scheduled_Build_Ref__c LIKE '%Industries.INS%FSC%'"
        else
            case "$v" in
                CME) FILT="Industries.CME" ;;
                INS) FILT="Industries.INS" ;;
                OS)  FILT="Industries.OS"  ;;
            esac
            CAB_FILTER_Q="Scheduled_Build_Ref__c LIKE '%${VERSION}%' AND Scheduled_Build_Ref__c LIKE '%${FILT}%' AND (NOT Scheduled_Build_Ref__c LIKE '%FSC%')"
        fi
        EXP_Q=$(sf data query --target-org gus --json --query \
            "SELECT Id FROM CAB_Patch_Candidate__c WHERE $CAB_FILTER_Q AND Stage__c IN ('Awaiting Approval', 'Pending Release', 'Close') AND Work__c != null") || {
                echo "❌ SOQL failed for CAB-candidate count ($v)" >&2; exit 1; }
        EXPECTED_CHILDREN=$(echo "$EXP_Q" | jq '.result.totalSize')
    fi

    echo ""
    echo "── $v ────────────────────────────────────"
    if [ -n "$EPIC_ID" ]; then echo "  ✅ Epic         : $EPIC_NM"; echo "     $(ep_link "$EPIC_ID")"
    else                       echo "  ❌ Epic         : MISSING"; ALL_OK=false; fi
    if [ -n "$WI_ID" ];   then echo "  ✅ RM WI        : $WI_NM"; echo "     $(wi_link "$WI_ID")"
    else                       echo "  ❌ RM WI        : MISSING"; ALL_OK=false; fi
    if [ -n "$PD_ID" ];   then echo "  ✅ Package WI   : $PD_NM"; echo "     $(wi_link "$PD_ID")"
    else                       echo "  ❌ Package WI   : MISSING"; ALL_OK=false; fi

    if [ -n "$WI_ID" ]; then
        if [ "$CHILD_COUNT" -ge "$EXPECTED_CHILDREN" ] && [ "$EXPECTED_CHILDREN" -gt 0 ]; then
            echo "  ✅ Child links  : $CHILD_COUNT / $EXPECTED_CHILDREN linked"
        elif [ "$EXPECTED_CHILDREN" -eq 0 ]; then
            echo "  ℹ️  Child links  : no CAB candidates for this vertical"
        else
            echo "  ❌ Child links  : $CHILD_COUNT / $EXPECTED_CHILDREN linked"
            ALL_OK=false
        fi
    fi

    if [ -n "$EPIC_ID" ] && [ -n "$WI_ID" ] && [ -n "$PD_ID" ]; then
        COMPLETE_LIST="$COMPLETE_LIST $v"
    else
        INCOMPLETE_LIST="$INCOMPLETE_LIST $v"
    fi
done

COMPLETE_LIST=$(echo "$COMPLETE_LIST"     | xargs)
INCOMPLETE_LIST=$(echo "$INCOMPLETE_LIST" | xargs)

echo ""
echo "========================================"
if [ "$ALL_OK" = true ]; then
    echo "✅ All approved verticals are complete."
else
    echo "⚠️  Incomplete verticals: ${INCOMPLETE_LIST:-(none)}"
    echo "   Re-run \`bash patch.sh weekly patch $VERSION\` to attempt the"
    echo "   missing pieces. The script is idempotent — completed work is skipped."
fi
echo "========================================"

# ─────────────────────────────────────────────────────────────────────────────
# Slack post payload — only verticals that completed all 3 steps end up in
# .slack-post-data.json (already produced by create-package-drops.sh for the
# verticals passed to it). After this script returns, the SKILL handler posts
# the file to Slack and registers thread timestamps in patch-state.json.
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "📝 Slack payload: $SCRIPT_DIR/.slack-post-data.json"
echo "   Next: Claude posts DM + channel message + FYA thread reply per vertical,"
echo "         then records thread timestamps via monitor-builds.py --add-thread."
echo ""

if [ "$ALL_OK" = true ]; then
    exit 0
else
    exit 1
fi
