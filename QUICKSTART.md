# Quick Start Guide - GUS Epic Automation

## What This Does

Automates creation of GUS epics for different verticals (CME, INS, OS, INS-FSC) by:
- Cloning from a reference epic for each vertical
- Auto-filling dates from a release schedule
- Generating proper epic names
- Linking to builds
- Setting Epic Health Comments

## Setup (5 minutes)

### Step 1: Run Setup Script

```bash
cd /Users/aarti.somani/.aisuite/notebook/2026-04-23
./setup-config.sh
```

This will guide you through:
1. **Entering reference epic IDs** for each vertical you want to support
2. **Setting up the release schedule** with dates from Confluence

### Step 2: Find Your Reference Epic IDs

For each vertical you want to automate:

1. Go to GUS: https://gus.lightning.force.com
2. Search for a recent Patch epic (e.g., search: `Industries.CME 260.10 Patch`)
3. Open the epic
4. Copy the ID from the URL (the part that looks like `a3QEE000002JFqD2AW`)
5. Enter it when the setup script asks

**Example:**
```
URL: https://gus.lightning.force.com/lightning/r/ADM_Epic__c/a3QEE000002JFqD2AW/view
Epic ID: a3QEE000002JFqD2AW
```

### Step 3: Add Release Dates

The setup script will create `release-schedule.json`. Update it with dates from:
https://confluence.internal.salesforce.com/spaces/RELEASE/pages/376178015/Release+Tracking

Format:
```json
{
  "260.11": {
    "start": "2026-04-24",
    "last_merge": "04/29",
    "sign_off": "05/05",
    "release": "2026-05-06"
  },
  "260.12": {
    "start": "2026-05-08",
    "last_merge": "05/13",
    "sign_off": "05/19",
    "release": "2026-05-20"
  }
}
```

## Usage

### Create a Patch Epic

```bash
./clone-epic-v2.sh <VERTICAL> <VERSION> Patch
```

**Examples:**

```bash
# Create CME 260.11 Patch
./clone-epic-v2.sh CME 260.11 Patch

# Create INS 260.12 Patch
./clone-epic-v2.sh INS 260.12 Patch

# Create OS 260.13 Patch
./clone-epic-v2.sh OS 260.13 Patch

# Create INS-FSC 260.11 Patch
./clone-epic-v2.sh INS-FSC 260.11 Patch
```

### What You'll See

1. Script validates inputs
2. Shows the dates it found
3. Fetches reference epic
4. Shows a preview of what will be created
5. Asks for confirmation (y/n)
6. Creates the epic
7. Shows the GUS URL

## Files Created

After setup, you'll have:

- ✅ `clone-epic-v2.sh` - Main automation script
- ✅ `epic-config.json` - Your vertical configurations
- ✅ `release-schedule.json` - Your release schedule
- ✅ `setup-config.sh` - Helper for initial setup
- ✅ `README-epic-automation.md` - Full documentation

## Maintenance

### Add a New Release Version

Edit `release-schedule.json` and add the new version:

```bash
vi release-schedule.json
```

### Update a Reference Epic

Edit `epic-config.json` and update the epic ID:

```bash
vi epic-config.json
```

### Add a New Vertical

1. Edit `epic-config.json`
2. Add a new entry under "verticals"
3. Update `VALID_VERTICALS` in `clone-epic-v2.sh`

## Troubleshooting

**"Version not found"**
→ Add it to `release-schedule.json`

**"No reference epic configured"**
→ Add the reference epic ID to `epic-config.json` for that vertical

**"Build not found"**
→ Script will continue without linking to a build (this is OK)

**Need to re-authenticate?**
```bash
sf org login web --instance-url https://gus.my.salesforce.com --alias gus
```

## What We Created Today

We already created one epic manually to test:
- **Epic:** Industries.CME 260.11 Patch
- **ID:** a3QEE000002MM5Z2AW
- **URL:** https://gus.lightning.force.com/lightning/r/ADM_Epic__c/a3QEE000002MM5Z2AW/view

This serves as the reference for future CME patch epics (ID: a3QEE000002JFqD2AW for 260.10).

## Next Steps

1. ✅ Run `./setup-config.sh` to configure your verticals
2. ✅ Test with one vertical: `./clone-epic-v2.sh CME 260.12 Patch`
3. ✅ Once working, configure remaining verticals
4. ✅ Update release schedule as new versions are announced

Need help? Check the full README: `README-epic-automation.md`
