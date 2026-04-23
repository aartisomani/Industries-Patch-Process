# GUS Epic Automation - Cheat Sheet

## 📍 Location
```bash
cd ~/repos/gus-epic-automation
```

## 🚀 Common Commands

### Create All 4 Verticals
```bash
./clone-epic-v3.sh CME/INS/OS/INS-FSC 260.11 Patch
```

### Create Specific Verticals
```bash
./clone-epic-v3.sh CME/INS 260.12 Patch
./clone-epic-v3.sh OS 260.13 Patch
```

## 📝 Add New Version

1. Edit release schedule:
```bash
vi release-schedule.json
```

2. Add entry:
```json
{
  "260.13": {
    "start": "2026-06-01",
    "last_merge": "06/06",
    "sign_off": "06/12",
    "release": "2026-06-13"
  }
}
```

3. Save and commit:
```bash
git add release-schedule.json
git commit -m "Add 260.13 schedule"
```

## 🔑 Date Formats

- **start** and **release**: `YYYY-MM-DD` (for GUS fields)
- **last_merge** and **sign_off**: `MM/DD` (for Health Comments)

## 🎯 Available Verticals

- `CME` - Industries.CME
- `INS` - Industries.INS
- `OS` - Industries.OS
- `INS-FSC` - Industries.INS-FSC

## 🔧 Reference Epic IDs

Already configured in `epic-config.json`:
- CME: `a3QEE000002JFqD2AW`
- INS: `a3QEE000002JFtR2AW`
- OS: `a3QEE000002JFv32AG`
- INS-FSC: `a3QEE000002JXwn2AG`

## 🐛 Quick Fixes

**Auth Error?**
```bash
sf org login web --instance-url https://gus.my.salesforce.com --alias gus
```

**Version Not Found?**
```bash
# Add it to release-schedule.json first
```

**Test Without Creating?**
```bash
# Preview stops at confirmation - just type 'n'
./clone-epic-v3.sh CME 260.11 Patch
```

## 💾 Backup/Version Control

```bash
# View changes
git status
git diff

# Commit changes
git add .
git commit -m "Your message"

# View history
git log --oneline
```

## 📊 What Gets Created

✅ Epic Name: `Industries.{VERTICAL} {VERSION} Patch`  
✅ Health: `New`  
✅ Dates from schedule  
✅ Health Comments: `Last merge: XX/XX, Sign off: XX/XX, Release: XX/XX`  
✅ Scheduled Build: Not set (manual)  
✅ Project/Category: From reference epic

---

**Keep this handy!** 🎯
