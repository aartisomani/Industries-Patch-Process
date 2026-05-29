---
name: Industries-patch-process
description: >
  End-to-end automation for Industries CME/INS/OS/INS-FSC weekly patch releases.
  Friday: epics, RM work items, package drops, Slack notifications.
  Thursday: read build threads, post GUS chatter to tech writers.
  Deployment Day: Slack kickoff message and per-vertical sign-offs on the Release record.
trigger: >
  Use when the user says "run weekly patch", "create release", "check builds",
  "run thursday", "run friday", "run deploy", "deployment day", "add signoffs",
  or mentions a patch version like 262.8 or 260.14.
---

# Industries Patch Process

Automates the weekly patch release cycle for Industries CME/INS/OS/INS-FSC verticals.

## Skill invocation menu (FROZEN — do not change based on session context)

When the user invokes `/industries-patch-process`, Claude MUST present
exactly these options via `AskUserQuestion`, in this order, every time —
regardless of what's pending in `patch-state.json` or where we left off in
the previous session. The menu is the user's stable entry point; dynamic
"helpful" reordering breaks muscle memory.

| Option label | What it runs |
|---|---|
| **Friday — Create Release** | `bash patch.sh weekly patch <V>` (CAB → epics → RM WIs → package WIs → child links → Slack → tracker block) |
| **Thursday — Check Builds** | `bash patch.sh check builds <V>` (read green-build threads → GUS chatter → mark done). The doc heading below is "Build Check Workflow" — same step, just a clearer name. |
| **Deployment Day** | `bash patch.sh deploy <V>` (Slack kickoff → per-vertical sign-offs on the Release record). |
| **Just sync schedule** | `python3 sync-schedule.py` only (refresh `release-schedule.json` from the Non Core Google Sheet — no GUS or Slack writes). |
| **Check status only** | `bash patch.sh check builds <V> --status` (read-only display of `patch-state.json` for a version). |

After the user picks, ask which version (only if the chosen option needs
one — sync-schedule does not).

## Repo location

```
~/repos/gus-patch-tickets/
```

All commands must be run from this directory (or with full path).

---

## Key people and IDs

| Person | Role | Slack ID | GUS ID |
|--------|------|----------|--------|
| Aarti Somani | RM | U098NUEJ6G4 | — |
| Amarendar Musham | RE POC | U08TFFLU9HP | 005EE00000ba6uPYAQ |
| Sanjit Roy | TW (CME) | U06TTC14ASU | 005EE00000NW2sgYAD |
| Rehmanshareef Shaik | TW (INS / INS-FSC) | U06DDNPV7EC | 005EE00000LaiGAYAZ |
| Swati Nair | TW (OS) | U06EM6DMV2A | 005EE00000LzRX3YAN |
| Rasmi Radhakrishnan | OS Chatter mention | U0626CBFYJ2 | 005EE00000JUx4XYAT |

Slack channel: `#industries-vlocity-release_patch_private` → `G026TENPY74`

---

## Configuration files

| File | Purpose |
|------|---------|
| `release-schedule.json` | Dates per version; `"monthly": true` for monthly patches |
| `epic-config.json` | Reference epic IDs for all 4 verticals |
| `tech-writer-config.json` | Tech writer GUS + Slack IDs per vertical |
| `patch-state.json` | Work item IDs + Slack thread timestamps per version |
| `workitem-config.json` | Reference RM work item IDs per vertical |
| `package-drop-config.json` | Reference package drop WI IDs per vertical |

### Monthly patch versions (as of 2026-05-22)
`262.3`, `262.7`, `262.11`, `262.15` — flagged with `"monthly": true` in `release-schedule.json`.

---

## FRIDAY WORKFLOW — Create Release

### Command

```bash
cd ~/repos/gus-patch-tickets
bash patch.sh run weekly patch <VERSION>
```

**Example:**
```bash
bash patch.sh run weekly patch 262.8
```

This calls `weekly-patch.sh` which:
1. Checks CAB approvals for the version
2. For each approved vertical, calls `create-release.sh <vertical> <VERSION> Patch`

### What create-release.sh does (in order)

**Pre-step — Sync schedule (automatic)**
```bash
python3 sync-schedule.py
```
Auto-syncs `release-schedule.json` from the Non Core Google Sheet via MCP proxy. Non-fatal — never blocks the run.

**Step 1 — Create Epics** (`clone-epic-v3.sh`)
- Creates `Industries.<VERTICAL> <VERSION> Patch` epic per vertical
- Monthly patch: name becomes `Industries.<VERTICAL> <VERSION> Monthly Patch`
- Clones fields from reference epic in `epic-config.json`
- Sets dates from `release-schedule.json`

**Step 2 — Create RM Work Items** (`create-work-items.sh`)
- Subject: `[Vlocity-<VERTICAL>] Patch <VERTICAL> <VERSION> (<release name>)`
- Monthly: `[Vlocity-<VERTICAL>] Monthly Patch <VERTICAL> <VERSION> (<release name>)`
- Type: User Story, Status: New
- Links to epic created in Step 1
- Posts Chatter comment to the WI tagging the tech writer (GUS REST API mention)
- OS vertical: also mentions Rasmi Radhakrishnan with "FYI"

**Step 3 — Create Package Drop WIs** (`create-package-drops.sh`)
- ⚠️ **NOT auto-confirmed** — 30-day POC check must be answered by a human
- Subject: `[Vlocity-<VERTICAL>] Package drop for version <VERTICAL> <VERSION>`
- Monthly: appends `Monthly` at the end
- Writes `.slack-post-data.json` with DM + channel Slack payloads

### After the script completes — Post Slack notifications

The script does NOT auto-post Slack. After it finishes:

1. Read `.slack-post-data.json`
2. For each entry, send via Slack MCP tool:
   - DM to Aarti Somani (`U098NUEJ6G4`)
   - Channel post to `#industries-vlocity-release_patch_private` (`G026TENPY74`)
3. Immediately reply in the channel thread: `<@U08TFFLU9HP> FYA`
4. Save thread timestamps to `patch-state.json` using:
   ```bash
   python3 monitor-builds.py --version <VERSION> --add-thread <VERTICAL> <CHANNEL_ID> <THREAD_TS>
   ```

### After Slack — Generate Vlocity Tracker block

Auto-runs after thread timestamps are saved. Pulls Epic / RM WI / Package
WI / CAB candidates from GUS and prints a paste-ready row block matching
the existing pattern in [FY26 Release Tracking Sheet](https://docs.google.com/spreadsheets/d/1h57__av4D-Rk_0U2zhPP-A-Ux75xcJ-Ln9Frb3COzmA/edit?gid=2117744889#gid=2117744889).

```bash
python3 tracker-block.py <VERSION>
```

Claude renders the output **as a fenced TSV block in chat** so the user can
copy and paste at the top of the sheet (Ctrl/Cmd+V works directly — Sheets
respects tab delimiters). The script also writes `.tracker-block.tsv` next
to itself for re-paste later.

The block includes:
- Banner row: version + `Running` + schedule string.
- CAB section: one row per CAB candidate (Cloud / PATCH# / Patch Candidate
  W# / Scheduled Build).
- RM section: one row per vertical (RM ticket / Devops Ticket / Package
  numbers blank — Thursday fills it / Child Record Added? = Yes).

If the script can't find CAB candidates for the version it exits 1 and
Claude reports `❌ No CAB candidates found for <VERSION>; tracker block
skipped.` — non-fatal for the rest of the Friday flow.

### Slack message format

```
Please open the [Monthly] Patch branch <VERTICAL> <VERSION> (post upmerge). Here is the GUS Work W-XXXXXXXX
Team kindly make sure PR has two level of approvals (before sharing), one of which should be the Manager Approval. Also ensure that PR builds are not failing.
For this patch Aarti Somani will be the RM and Amarendar Musham will be Release Engineer. Please tag us for any assistance.
Schedule:
Last Merge: MM/DD/YYYY(Day at 11:30 AM IST)
Q3 Sign Off: MM/DD/YYYY(Day at 03:00 PM IST)
Release Deployment: MM/DD/YYYY
```
Note: names inside the code block are plain text (not @mentions — those don't render in ``` blocks).
The thread reply `<@U08TFFLU9HP> FYA` is posted outside the code block so the mention renders.

### Friday completion checklist

- [ ] CAB approvals checked
- [ ] Epics created in GUS
- [ ] RM work items created in GUS
- [ ] Package drop WIs created (POC check answered)
- [ ] Slack DM sent to Aarti
- [ ] Slack channel message posted
- [ ] Thread reply `@Amarendar Musham FYA` posted
- [ ] Thread timestamps saved to `patch-state.json`
- [ ] Vlocity Tracker block rendered in chat for paste

---

## BUILD CHECK WORKFLOW — Check Builds

> Historically called "Thursday Workflow" — kept the operational name for
> chat references, but this step runs whenever the build is triggered after
> last-merge, which varies by patch (sometimes Wed, sometimes Thu, sometimes
> later). Run it once a green build appears in the Slack thread.

### Command

```bash
cd ~/repos/gus-patch-tickets
bash patch.sh run check builds <VERSION>
```

**Example:**
```bash
bash patch.sh run check builds 262.8
```

Or check status only:
```bash
bash patch.sh run check builds 262.8 --status
```

### What happens

1. `check-builds.sh` calls `monitor-builds.py --pending`
2. Script prints each pending vertical with:
   - Slack channel ID + thread timestamp
   - GUS work item ID
   - Tech writer name + Slack/GUS IDs
3. Claude reads each Slack thread via MCP Slack tool
4. Claude finds the IREBuildNotifier message and extracts:
   - Vertical, Build Job, Namespace, Package Version, Install URL
5. Claude posts to GUS WI chatter via REST API, tagging the tech writer:
   ```
   POST /services/data/v64.0/chatter/feed-elements
   ```
   With a `{"type":"Mention","id":"<TW_GUS_ID>"}` segment
6. Mark each vertical done:
   ```bash
   python3 monitor-builds.py --version <VERSION> --mark-done <VERTICAL> \
     --workitem-id <WI_ID> \
     --build-details '{"build_job":"...","namespace":"...","package_version":"...","install_url":"..."}'
   ```

### Fallback — Slack thread discovery (REQUIRED before bailing out)

If `monitor-builds.py --pending` reports `No Slack threads registered for version
<VERSION>`, **do NOT stop**. The Friday step that records the thread sometimes
fails silently (Slack MCP outage, run interrupted, repo state on a different
machine). Always attempt to recover the thread by scanning the channel before
asking the user.

**Procedure (Claude executes this automatically):**

1. **Scan the patch channel for the version.** Use the Slack MCP search scoped
   to `G026TENPY74`. Try multiple query forms because the announcement format
   has changed slightly across versions:
   ```
   slack_search_public(query="in:#industries-vlocity-release_patch_private \"<VERSION>\" \"Patch branch\"")
   slack_search_public(query="in:#industries-vlocity-release_patch_private \"GUS Work\" \"<VERSION>\"")
   ```
   For monthly patches, also try `"Monthly Patch branch" "<VERSION>"`.

2. **If search returns nothing**, fall back to `slack_read_channel` on
   `G026TENPY74` paginated back ~14 days and grep replies locally for the
   version string. Prefer parent messages (no `thread_ts`) that contain
   `Patch branch <VERTICAL> <VERSION>` AND `GUS Work W-`.

3. **Identify the right parent per vertical.** Each vertical (CME / INS / OS /
   INS-FSC) gets its own thread. The parent must:
   - be authored by the RM (`U098NUEJ6G4`) or the MCP-app proxy
     (`U095RFJ8GTH`),
   - contain the literal `<VERSION>` and `Patch branch` (or `Monthly Patch
     branch` for monthly versions),
   - be a top-level message (no `thread_ts` of its own).

4. **Cross-check the Work Item.** Pull the `W-XXXXXXXX` string from the message
   body and confirm it matches the RM WI subject in GUS:
   ```bash
   sf data query --target-org gus -q "SELECT Id, Name, Subject__c FROM ADM_Work__c WHERE Name='W-XXXXXXXX'"
   ```
   The subject must look like `[Vlocity-<VERTICAL>] Patch <VERTICAL> <VERSION> ...`
   (or `Monthly Patch ...`). Reject anything that says "Package Creation and
   Deployment" — that's the package drop WI, not the RM WI.

5. **Show the candidate(s) to the user and confirm** before registering — one
   confirmation covers all verticals found. After approval:
   ```bash
   python3 monitor-builds.py --version <VERSION> --add-thread <VERTICAL> G026TENPY74 <THREAD_TS>
   ```
   Also backfill the RM work item if `patch-state.json` is missing it for that
   vertical (edit the file directly or re-run the Friday step that records WI
   IDs).

6. **Re-run** `bash patch.sh check builds <VERSION>` and proceed with the normal
   Thursday flow.

Same fallback applies to Deployment Day if you need the announcement thread for
context — but deployment itself is stateless and finds the Release record from
GUS, so deploy can proceed without it.

### Build check completion checklist

- [ ] All pending Slack threads read (or recovered via fallback)
- [ ] Build details extracted for each vertical
- [ ] GUS chatter posted with tech writer mention
- [ ] Verticals marked done in `patch-state.json`

---

## DEPLOYMENT DAY WORKFLOW — Post Slack + Add Sign-offs

Runs on the deployment day (Wednesday/Thursday after Q3 sign-off). Assumes the
Jenkins job has already created the GUS Release record and linked Change Cases.

### Command

```bash
cd ~/repos/gus-patch-tickets
bash patch.sh run deploy <VERSION>
```

**Examples:**
```bash
bash patch.sh run deploy 262.8           # full flow: Slack + sign-offs
bash patch.sh run deploy 262.8 slack     # only Slack message
bash patch.sh run deploy 262.8 signoffs  # only sign-offs
```

### Stateless design

Each step queries GUS directly for the Release record by version. Pattern:
```sql
SELECT Id, Name FROM ADM_Release__c
WHERE Name LIKE '%<VERSION>%Patch%' AND Application__r.Name = 'Industries'
ORDER BY CreatedDate DESC LIMIT 1
```
No `patch-state.json` involvement. Steps can run independently in any order
and from any machine that has `sf` auth.

### What deploy-patch.sh does

**Step 1 — Generate Deployment Slack Message** (`post-deploy-slack.sh`)
- Queries GUS for the Release record by version
- Reads release date and `monthly` flag from `release-schedule.json`
- Writes `.deploy-slack-data.json` with channel + message + thread reply payload
- Claude (via this skill) reads the file and posts to
  `#industries-vlocity-release_patch_private` (`G026TENPY74`)
- Channel mention `<@U08TFFLU9HP> FYA — deployment kickoff` posted as thread reply

**Step 2 — Add Sign-offs to Release Record** (`add-signoffs.sh`)
- Queries GUS for the Release record by version
- Reads `signoff-config.json` for per-vertical Application Approver IDs
- For each approver, creates `ADM_Signoff__c` linked to the Release with:
  - `Release__c` = Release record
  - `Release_Approver__c` = `ADM_Application_Approver__c` ID (the AA-XXXXX record)
  - `Approver__c` = the User behind that Application Approver
  - `Approval_Status__c = 'Pending'`
  - Required booleans: `checked__c=false`, `Approval_Comments_Available__c=false`,
    `Auto_Approved__c=false`
- Idempotent — skips approvers that already have a sign-off on this Release

### Optional helper

```bash
./find-release-record.sh <VERSION>           # any vertical
./find-release-record.sh <VERSION> CME       # filter by vertical
```
Use this to verify which Release record will be picked up before running the
full flow. Returns matching `ADM_Release__c` records ordered by created date.

### signoff-config.json structure

```json
{
  "verticals": {
    "CME":     { "approvers": ["a2VEE000..."] },
    "INS":     { "approvers": ["a2VEE000..."] },
    "OS":      { "approvers": ["a2VEE000..."] },
    "INS-FSC": { "approvers": ["a2VEE000..."] }
  },
  "_shared_approvers": {
    "approvers": []
  }
}
```
Each `approvers` entry is an `ADM_Application_Approver__c` Salesforce ID
(starts with `a2VEE`), NOT the AA-XXXXX display name. Get IDs from
[Industries Application Approvers](https://gus.lightning.force.com/lightning/r/ADM_Application__c/a2WB00000006F2ZMAU/related/Application_Approvers__r/view).

### Deployment day completion checklist

- [ ] Jenkins job completed (Release record + Change Cases exist in GUS)
- [ ] `find-release-record.sh <VERSION>` confirms the right record
- [ ] Deployment Slack message posted to channel
- [ ] Thread reply `@Amarendar Musham FYA — deployment kickoff` posted
- [ ] Per-vertical sign-offs created (`signoff-config.json` filled in)
- [ ] No "Failed" entries in the add-signoffs.sh summary

---

## Monthly patch behaviour

When `release-schedule.json` has `"monthly": true` for a version, ALL scripts automatically adjust:

| Item | Regular Patch | Monthly Patch |
|------|--------------|---------------|
| Epic name | `Industries.CME 262.8 Patch` | `Industries.CME 262.7 Monthly Patch` |
| RM WI subject | `[Vlocity-CME] Patch CME 262.8 (...)` | `[Vlocity-CME] Monthly Patch CME 262.7 (...)` |
| Package drop subject | `...Package drop for version CME 262.8` | `...Package drop for version CME 262.7 Monthly` |
| Slack message | `Please open the Patch branch...` | `Please open the Monthly Patch branch...` |

No manual changes needed — the flag drives everything.

---

## Release schedule sync

The schedule is auto-synced from the Non Core Google Sheet before every Friday run:

- **Sheet**: [Non Core tab](https://docs.google.com/spreadsheets/d/1Lxgeuu7eS-FTtmk_G-uUJS5ViIvE3pov_2WyuxFPtYQ/edit#gid=2019019728)
- **Script**: `sync-schedule.py`
- **Auth**: Uses existing Google MCP proxy — no extra setup
- **Preserves**: `status`, `cancelled` flags and any manually added fields
- **Updates**: dates (`start`, `last_merge`, `sign_off`, `release`) and `monthly` flag

To run manually:
```bash
python3 sync-schedule.py
```

---

## GUS objects reference

| Object | Purpose |
|--------|---------|
| `ADM_Epic__c` | Epics — one per vertical per version |
| `ADM_Work__c` | Work items — RM WI and Package Drop WI |
| `ADM_Build__c` | Builds — `Industries.<VERTICAL> <VERSION>` |
| `CAB_Patch_Candidate__c` | CAB approvals — checked on Friday |
| `ADM_Release__c` | Release record — created by Jenkins on deploy day |
| `ADM_Release_Case_Status__c` | Change Cases linked to the Release (created by Jenkins) |
| `ADM_Signoff__c` | Sign-off records on the Release (created by `add-signoffs.sh`) |
| `ADM_Application_Approver__c` | Approver master list for `Industries` Application |

---

## Troubleshooting

**Version not in release-schedule.json**
→ Run `python3 sync-schedule.py` first, or add manually then re-run.

**GUS auth error**
```bash
sf org login web --instance-url https://gus.my.salesforce.com --alias gus
```

**Slack MCP unavailable**
→ Restart Claude Code / AI Suite.

**Package drop POC check blocked**
→ This is intentional. Verify Amarendar Musham is still the RE POC before proceeding.
   File `.last-poc-check` tracks the last time this was confirmed (30-day cadence).

**Duplicate Slack messages**
→ Check `.slack-post-data.json` — confirm it hasn't been posted already before re-running.

**Chatter not showing mention**
→ Must use REST API (`/services/data/v64.0/chatter/feed-elements`) with `"type":"Mention"` segment.
   Do NOT use `sf data create record --sobject FeedItem` — that only posts plain text.
