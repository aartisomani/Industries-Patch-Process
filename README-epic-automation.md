# GUS Epic Cloning Automation

Automated script to clone GUS epics for different verticals (CME, INS, OS, INS-FSC) and types (Patch, ERR).

## Files

- **`clone-epic-v2.sh`** - Main automation script
- **`epic-config.json`** - Configuration for each vertical (reference epics)
- **`release-schedule.json`** - Release dates from Confluence
- **`epic-config-example.json`** - Example configuration
- **`release-schedule-example.json`** - Example schedule

## Setup

### 1. Create Configuration Files

Copy the example files and update with your data:

```bash
cd /Users/aarti.somani/.aisuite/notebook/2026-04-23

# Copy and edit the configuration
cp epic-config-example.json epic-config.json

# Copy and edit the release schedule
cp release-schedule-example.json release-schedule.json

# Make the script executable
chmod +x clone-epic-v2.sh
```

### 2. Configure Verticals

Edit `epic-config.json` to add reference epic IDs for each vertical:

```json
{
  "verticals": {
    "CME": {
      "patch_reference_epic": "a3QEE000002JFqD2AW",
      "err_reference_epic": "",
      "description": "Industries.CME"
    },
    "INS": {
      "patch_reference_epic": "<INSERT_INS_PATCH_EPIC_ID>",
      "err_reference_epic": "",
      "description": "Industries.INS"
    }
  }
}
```

**How to find reference epic IDs:**
- Go to GUS and find a recent Patch epic for each vertical (e.g., "Industries.CME 260.10 Patch")
- Copy the epic ID from the URL (the `a3Q...` part)
- Add it to the configuration

### 3. Update Release Schedule

Edit `release-schedule.json` with dates from the Confluence page:
https://confluence.internal.salesforce.com/spaces/RELEASE/pages/376178015/Release+Tracking

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

### Basic Command

```bash
./clone-epic-v2.sh <VERTICAL> <VERSION> <TYPE>
```

### Parameters

- **VERTICAL**: `CME` | `INS` | `OS` | `INS-FSC`
- **VERSION**: Release version (e.g., `260.11`)
- **TYPE**: `Patch` | `ERR`

### Examples

**Create a CME Patch epic for 260.11:**
```bash
./clone-epic-v2.sh CME 260.11 Patch
```

**Create an INS Patch epic for 260.12:**
```bash
./clone-epic-v2.sh INS 260.12 Patch
```

**Create an OS Patch epic for 260.13:**
```bash
./clone-epic-v2.sh OS 260.13 Patch
```

### What the Script Does

1. ✅ Validates vertical and type
2. ✅ Looks up dates from `release-schedule.json`
3. ✅ Fetches the reference epic for that vertical
4. ✅ Clones all relevant fields (Owner, Project, Category, etc.)
5. ✅ Auto-generates the new epic name (replaces version number)
6. ✅ Links to the correct build if it exists
7. ✅ Sets Epic Health Comments with milestone dates
8. ✅ Shows a preview and asks for confirmation
9. ✅ Creates the epic and displays the GUS URL

### Sample Output

```
=== Creating Epic for CME 260.11 Patch ===

Dates from schedule:
  Start Date: 2026-04-24
  Last Merge: 04/29
  Sign Off: 05/05
  Release: 2026-05-06

Using reference epic: a3QEE000002JFqD2AW
Fetching reference epic details...
New Epic Name: Industries.CME 260.11 Patch

Looking up build for version 260.11...
Found Build ID: a06EE00000Nt5rZYAR

=== EPIC CREATION PREVIEW ===
Name: Industries.CME 260.11 Patch
Vertical: CME
Type: Patch
Category: Operations
Start Date: 2026-04-24
End Date: 2026-05-06
Health Comments: Last merge: 04/29, Sign off: 05/05, Release: 05/06
Build: 260.11 (a06EE00000Nt5rZYAR)
===========================

Create this epic? (y/n):
```

## ERR Type Epics

ERR type epics are not yet implemented. Once requirements are defined, the script will be updated to support them.

## Maintenance

### Adding New Versions

When new release versions are announced, update `release-schedule.json`:

```bash
# Edit the file
vi release-schedule.json

# Or use jq to add programmatically
jq '. += {"260.13": {"start": "2026-05-22", "last_merge": "05/27", "sign_off": "06/02", "release": "2026-06-03"}}' release-schedule.json > tmp.json && mv tmp.json release-schedule.json
```

### Adding New Verticals

To add a new vertical:

1. Add it to `epic-config.json` with a reference epic ID
2. Update the `VALID_VERTICALS` variable in the script

### Troubleshooting

**"Version not found in release schedule"**
- Add the version to `release-schedule.json`

**"No patch reference epic configured for vertical"**
- Add the reference epic ID to `epic-config.json` for that vertical

**"Build not found in GUS"**
- The script will continue but won't link to a build
- Verify the build exists in GUS or create it first

**Authentication errors**
- Run: `sf org login web --instance-url https://gus.my.salesforce.com --alias gus`

## Future Enhancements

- [ ] Automatic Confluence date fetching (requires auth setup)
- [ ] ERR type epic support
- [ ] Bulk creation for multiple verticals
- [ ] Pre-flight validation checks
- [ ] Epic cloning from any source (not just reference epics)
