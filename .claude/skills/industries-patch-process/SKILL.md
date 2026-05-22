---
name: Industries-patch-process
description: >
  End-to-end automation for Industries CME/INS/OS/INS-FSC weekly patch releases.
  Use for Friday release creation (epics, RM work items, package drops, Slack) and
  Thursday build monitoring (read Slack threads, post GUS chatter).
trigger: >
  Use when the user says "run weekly patch", "create release", "check builds",
  "run thursday", "run friday", or mentions a patch version like 262.8 or 260.14.
---

# Industries Patch Process

Automates the weekly patch release cycle for Industries CME/INS/OS/INS-FSC verticals.

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

---

## THURSDAY WORKFLOW — Check Builds

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

### Thursday completion checklist

- [ ] All pending Slack threads read
- [ ] Build details extracted for each vertical
- [ ] GUS chatter posted with tech writer mention
- [ ] Verticals marked done in `patch-state.json`

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
