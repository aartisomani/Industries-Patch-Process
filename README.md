# GUS Epic Automation

Automated script to clone and create GUS epics for multiple verticals (CME, INS, OS, INS-FSC) in a single command.

## 🚀 Quick Start

```bash
cd ~/repos/gus-epic-automation

# Create epics for all 4 verticals
./clone-epic-v3.sh CME/INS/OS/INS-FSC 260.12 Patch

# Create epics for specific verticals
./clone-epic-v3.sh CME/INS 260.12 Patch
```

## 📋 Features

- ✅ **Multi-vertical support** - Create epics for all verticals in one command
- ✅ **Single confirmation** - One "y" for all epics instead of multiple
- ✅ **Automated date management** - Dates pulled from centralized schedule
- ✅ **Reference-based cloning** - Each vertical clones from its own reference epic
- ✅ **Summary report** - See all created epics with GUS links
- ✅ **Error resilient** - One failure doesn't stop the rest

## 📖 Documentation

- **[QUICKSTART.md](QUICKSTART.md)** - 5-minute getting started guide
- **[USAGE-GUIDE.md](USAGE-GUIDE.md)** - Full usage examples and comparison
- **[README-epic-automation.md](README-epic-automation.md)** - Complete technical documentation

## 🛠️ Setup

### Prerequisites

- Salesforce CLI (`sf`) installed
- Authenticated to GUS org: `sf org login web --instance-url https://gus.my.salesforce.com --alias gus`

### Configuration Files

1. **epic-config.json** - Maps verticals to reference epic IDs (already configured)
2. **release-schedule.json** - Contains release dates for each version

### Adding New Release Versions

Edit `release-schedule.json`:

```json
{
  "260.12": {
    "start": "2026-05-08",
    "last_merge": "05/13",
    "sign_off": "05/19",
    "release": "2026-05-20"
  }
}
```

## 📝 Usage Examples

### Create All Verticals for a Version

```bash
./clone-epic-v3.sh CME/INS/OS/INS-FSC 260.11 Patch
```

### Create Specific Verticals

```bash
# Only CME and INS
./clone-epic-v3.sh CME/INS 260.12 Patch

# Only one vertical
./clone-epic-v3.sh CME 260.13 Patch
```

## 🎯 What Gets Created

Each epic includes:
- **Name**: Industries.{VERTICAL} {VERSION} Patch
- **Category**: Operations (from reference epic)
- **Project**: Same as reference epic
- **Start/End Dates**: From release schedule
- **Health**: New
- **Health Comments**: "Last merge: XX/XX, Sign off: XX/XX, Release: XX/XX"
- **Scheduled Build**: Not set (manual assignment)

## 📊 Output Example

```
========================================
SUMMARY
========================================
Total epics to create: 4
Successfully created: 4
Failed: 0

✅ Successfully Created Epics:
  [CME] Industries.CME 260.11 Patch
      → https://gus.lightning.force.com/lightning/r/ADM_Epic__c/a3Q...
  [INS] Industries.INS 260.11 Patch
      → https://gus.lightning.force.com/lightning/r/ADM_Epic__c/a3Q...
  [OS] Industries.OS 260.11 Patch
      → https://gus.lightning.force.com/lightning/r/ADM_Epic__c/a3Q...
  [INS-FSC] Industries.INS-FSC 260.11 Patch
      → https://gus.lightning.force.com/lightning/r/ADM_Epic__c/a3Q...
========================================
```

## 🔧 Files

| File | Purpose |
|------|---------|
| `clone-epic-v3.sh` | Main automation script |
| `epic-config.json` | Vertical configurations (reference epic IDs) |
| `release-schedule.json` | Release schedule with dates |
| `setup-config.sh` | Interactive setup helper |
| `*-example.json` | Configuration templates |

## 🔄 Maintenance

### Update Release Schedule

When new versions are announced:

```bash
vi release-schedule.json
# Add the new version with dates
git add release-schedule.json
git commit -m "Add 260.12 release schedule"
```

### Update Vertical Configuration

If reference epics change:

```bash
vi epic-config.json
# Update the reference epic IDs
git add epic-config.json
git commit -m "Update CME reference epic"
```

## ⚠️ Important Notes

- **Separator is `/`** - Use forward slash: `CME/INS/OS`
- **No spaces** - `CME/INS` not `CME / INS`
- **Version must exist in schedule** - Add to `release-schedule.json` first
- **Type currently supports** - `Patch` only (ERR coming later)

## 🐛 Troubleshooting

**"Version not found in release schedule"**
→ Add it to `release-schedule.json`

**"No patch reference epic configured"**
→ Add the reference epic ID to `epic-config.json`

**GUS authentication error**
→ Run: `sf org login web --instance-url https://gus.my.salesforce.com --alias gus`

## 📜 License

Internal Salesforce tool - for Salesforce employees only.

## 👤 Author

Created with Claude Code assistance for GUS epic automation.

---

**Last Updated**: 2026-04-23  
**Version**: 3.0  
**Supported Verticals**: CME, INS, OS, INS-FSC
