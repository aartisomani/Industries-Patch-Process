# Complete Workflow - GUS Patch Automation

## 📋 Quick Reference

### Create Epics + Work Items for a New Patch

```bash
cd ~/repos/gus-patch-tickets

# 1. Add version to release schedule (if not exists)
vi release-schedule.json

# 2. Create epics for all verticals
./clone-epic-v3.sh CME/INS/OS/INS-FSC 260.12 Patch

# 3. Create work items for all verticals
./create-work-items.sh CME/INS/OS/INS-FSC 260.12 Patch
```

## 🎯 What Gets Created

### Epic (per vertical)
- Name: `Industries.{VERTICAL} {VERSION} Patch`
- Category: Operations
- Project: From reference epic
- Dates: From release schedule
- Health: New
- Health Comments: Last merge, Sign off, Release dates
- Scheduled Build: Not set

### Work Item (per vertical)
- Subject: `[Vlocity-{VERTICAL}] Patch {VERTICAL} {VERSION} (Spring 2026 Major release)`
- Type: User Story
- Status: New
- Epic: Linked to created epic
- Build: `Industries.{VERTICAL} {VERSION}`
- Details: Patch number and dates
- All other fields: Cloned from reference work item

## 🔧 Configuration Files

| File | Purpose | Current Status |
|------|---------|----------------|
| `epic-config.json` | Epic reference IDs | ✅ All 4 verticals configured |
| `workitem-config.json` | Work item reference IDs | ⚠️ Only CME configured |
| `release-schedule.json` | Release dates | ✅ 260.10, 260.11, 260.12 |

## ⚠️ TODO: Add Other Verticals

To enable work item creation for INS, OS, INS-FSC:

1. Find reference work items for each vertical (from 260.10 or similar)
2. Update `workitem-config.json`:

```json
{
  "verticals": {
    "CME": {
      "patch_reference_workitem": "a07EE00002XrJFVYA3"
    },
    "INS": {
      "patch_reference_workitem": "W-XXXXXXXX"  // Add this
    },
    "OS": {
      "patch_reference_workitem": "W-XXXXXXXX"  // Add this
    },
    "INS-FSC": {
      "patch_reference_workitem": "W-XXXXXXXX"  // Add this
    }
  }
}
```

## 📝 Example Session

```bash
$ cd ~/repos/gus-patch-tickets

$ ./clone-epic-v3.sh CME 260.11 Patch
✅ Created: Industries.CME 260.11 Patch
   → https://gus.lightning.force.com/lightning/r/ADM_Epic__c/...

$ ./create-work-items.sh CME 260.11 Patch
✅ W-22196169
   → https://gus.lightning.force.com/lightning/r/ADM_Work__c/...
```

## 🎉 Successfully Tested

- ✅ Epic creation: Industries.CME 260.11 Patch
- ✅ Work item creation: W-22196169
- ✅ All fields populated correctly
- ✅ RecordType validation passing

## 🚀 Next Steps

1. Get reference work item IDs for INS, OS, INS-FSC
2. Update `workitem-config.json`
3. Test with all 4 verticals
4. Add ERR type support (future)

---

**Last Updated:** 2026-04-23  
**Version:** 1.0 (Epics + Work Items)
