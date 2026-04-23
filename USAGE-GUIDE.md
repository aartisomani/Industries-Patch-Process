# Epic Automation - Usage Guide

## ✅ New Multi-Vertical Script (Recommended)

**File:** `clone-epic-v3.sh`

### Create Epics for Multiple Verticals at Once

```bash
# Create for all 4 verticals in ONE command
./clone-epic-v3.sh CME/INS/OS/INS-FSC 260.11 Patch

# Create for 3 verticals
./clone-epic-v3.sh CME/OS/INS-FSC 260.11 Patch

# Create for 2 verticals
./clone-epic-v3.sh CME/INS 260.11 Patch

# Create for 1 vertical (also works)
./clone-epic-v3.sh CME 260.11 Patch
```

### What You'll See

```
========================================
GUS EPIC BULK CREATION
========================================
Verticals: CME INS OS INS-FSC
Version: 260.11
Type: Patch
========================================

📅 Dates from schedule:
  Start Date: 2026-04-24
  Last Merge: 04/29
  Sign Off: 05/05
  Release: 2026-05-06

🔍 Looking up build for version 260.11...
✅ Found Build ID: a06EE00000Nt5rZYAR

========================================
PREVIEW - Will Create 4 Epic(s)
========================================

[1/4] Processing CME...
   Reference epic: a3QEE000002JFqD2AW
   New Epic Name: Industries.CME 260.11 Patch

[2/4] Processing INS...
   Reference epic: a3QEE000002JFtR2AW
   New Epic Name: Industries.INS 260.11 Patch

[3/4] Processing OS...
   Reference epic: a3QEE000002JFv32AG
   New Epic Name: Industries.OS 260.11 Patch

[4/4] Processing INS-FSC...
   Reference epic: a3QEE000002JXwn2AG
   New Epic Name: Industries.INS-FSC 260.11 Patch

========================================
FINAL PREVIEW
========================================
[1] Industries.CME 260.11 Patch
    Category: Operations
    Project ID: a1kEE000007G4LNYA0

[2] Industries.INS 260.11 Patch
    Category: Operations
    Project ID: <project-id>

[3] Industries.OS 260.11 Patch
    Category: Operations
    Project ID: <project-id>

[4] Industries.INS-FSC 260.11 Patch
    Category: Operations
    Project ID: <project-id>

Common to all epics:
  Start Date: 2026-04-24
  End Date: 2026-05-06
  Health: New
  Health Comments: Last merge: 04/29, Sign off: 05/05, Release: 05/06
  Build: 260.11 (a06EE00000Nt5rZYAR)
========================================

Create these 4 epic(s)? (y/n):
```

### After Confirmation

```
========================================
CREATING EPICS
========================================

[1/4] Creating epic for CME...
✅ Created: Industries.CME 260.11 Patch (a3QEE000002XXXXXX)

[2/4] Creating epic for INS...
✅ Created: Industries.INS 260.11 Patch (a3QEE000002YYYYYY)

[3/4] Creating epic for OS...
✅ Created: Industries.OS 260.11 Patch (a3QEE000002ZZZZZZ)

[4/4] Creating epic for INS-FSC...
✅ Created: Industries.INS-FSC 260.11 Patch (a3QEE000002AAAAAA)

========================================
SUMMARY
========================================
Total epics to create: 4
Successfully created: 4
Failed: 0

✅ Successfully Created Epics:
  [CME] Industries.CME 260.11 Patch
      → https://gus.lightning.force.com/lightning/r/ADM_Epic__c/a3QEE000002XXXXXX/view
  [INS] Industries.INS 260.11 Patch
      → https://gus.lightning.force.com/lightning/r/ADM_Epic__c/a3QEE000002YYYYYY/view
  [OS] Industries.OS 260.11 Patch
      → https://gus.lightning.force.com/lightning/r/ADM_Epic__c/a3QEE000002ZZZZZZ/view
  [INS-FSC] Industries.INS-FSC 260.11 Patch
      → https://gus.lightning.force.com/lightning/r/ADM_Epic__c/a3QEE000002AAAAAA/view

========================================
```

## 🔄 Old Single-Vertical Script (Still Works)

**File:** `clone-epic-v2.sh`

```bash
# Create one at a time
./clone-epic-v2.sh CME 260.11 Patch
./clone-epic-v2.sh INS 260.11 Patch
./clone-epic-v2.sh OS 260.11 Patch
./clone-epic-v2.sh INS-FSC 260.11 Patch
```

## 📊 Comparison

| Feature | v2 (Old) | v3 (New) ⭐ |
|---------|----------|------------|
| **Single vertical** | ✅ `./clone-epic-v2.sh CME 260.11 Patch` | ✅ `./clone-epic-v3.sh CME 260.11 Patch` |
| **Multiple verticals** | ❌ Run 4 times | ✅ `./clone-epic-v3.sh CME/INS/OS/INS-FSC 260.11 Patch` |
| **Confirmations** | 1 per epic (4 times) | 1 for all epics |
| **Summary report** | ❌ No | ✅ Yes |
| **Clickable URLs** | ✅ Yes | ✅ Yes (for all) |
| **Error handling** | Stops on failure | Continues, shows summary |

## 🎯 Common Use Cases

### Create All 4 Verticals for a New Patch

```bash
./clone-epic-v3.sh CME/INS/OS/INS-FSC 260.12 Patch
```

### Create Only Specific Verticals

```bash
# Only CME and INS
./clone-epic-v3.sh CME/INS 260.12 Patch

# Only OS
./clone-epic-v3.sh OS 260.12 Patch
```

### Create for Different Versions

```bash
# 260.11
./clone-epic-v3.sh CME/INS/OS/INS-FSC 260.11 Patch

# 260.12
./clone-epic-v3.sh CME/INS/OS/INS-FSC 260.12 Patch

# 262.1
./clone-epic-v3.sh CME/INS/OS/INS-FSC 262.1 Patch
```

## 🚀 Recommended Workflow

1. **Update release schedule** when new version is announced:
   ```bash
   vi release-schedule.json
   ```

2. **Create all epics at once**:
   ```bash
   ./clone-epic-v3.sh CME/INS/OS/INS-FSC 260.12 Patch
   ```

3. **Review the summary** and click on the GUS URLs to verify

## ⚠️ Important Notes

- **Separator is `/`** - Use forward slash to separate verticals
- **No spaces** - `CME/INS` not `CME / INS`
- **Order doesn't matter** - `CME/INS` or `INS/CME` works the same
- **Can mix and match** - Any combination of the 4 verticals
- **Single confirmation** - You only confirm once for all epics
- **Atomic by vertical** - If one fails, others still get created

## 🎉 Benefits of v3

✅ **Faster** - Create 4 epics in one command  
✅ **Fewer confirmations** - Just one "y" instead of 4  
✅ **Better visibility** - See all epics being created at once  
✅ **Summary report** - Know exactly what succeeded/failed  
✅ **Error resilient** - One failure doesn't stop the rest  

---

**Use v3 for everything!** It's backwards compatible with single verticals too.
