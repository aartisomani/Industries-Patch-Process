#!/bin/bash

# Interactive setup script for epic automation configuration

set -e

SCRIPT_DIR="$(dirname "$0")"
CONFIG_FILE="$SCRIPT_DIR/epic-config.json"
SCHEDULE_FILE="$SCRIPT_DIR/release-schedule.json"

echo "=== GUS Epic Automation - Configuration Setup ==="
echo ""

# Check if config already exists
if [ -f "$CONFIG_FILE" ]; then
    echo "Configuration file already exists: $CONFIG_FILE"
    read -p "Overwrite? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Keeping existing configuration."
        CONFIG_EXISTS=true
    else
        CONFIG_EXISTS=false
    fi
else
    CONFIG_EXISTS=false
fi

if [ "$CONFIG_EXISTS" = false ]; then
    echo ""
    echo "Setting up verticals configuration..."
    echo ""
    echo "For each vertical, you'll need to provide a reference Patch epic ID."
    echo "This is the epic that will be cloned when creating new patch epics."
    echo ""
    echo "To find the epic ID:"
    echo "  1. Go to GUS and find a recent Patch epic (e.g., 'Industries.CME 260.10 Patch')"
    echo "  2. Copy the epic ID from the URL (looks like: a3Q...)"
    echo ""

    # Initialize config JSON
    cat > "$CONFIG_FILE" << 'EOF'
{
  "verticals": {}
}
EOF

    # Add verticals
    VERTICALS=("CME" "INS" "OS" "INS-FSC")

    for vertical in "${VERTICALS[@]}"; do
        echo "--- Configuring $vertical ---"
        read -p "Do you want to configure $vertical? (y/n): " -n 1 -r
        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -p "Enter Patch reference epic ID for $vertical: " PATCH_EPIC_ID

            # Add to config
            jq ".verticals.\"$vertical\" = {
                \"patch_reference_epic\": \"$PATCH_EPIC_ID\",
                \"err_reference_epic\": \"\",
                \"description\": \"Industries.$vertical\"
            }" "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"

            echo "✓ $vertical configured"
        else
            echo "Skipping $vertical"
        fi
        echo ""
    done

    echo "✓ Configuration file created: $CONFIG_FILE"
fi

# Setup release schedule
echo ""
if [ -f "$SCHEDULE_FILE" ]; then
    echo "Release schedule file already exists: $SCHEDULE_FILE"
    read -p "Do you want to edit it? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        vi "$SCHEDULE_FILE"
    fi
else
    echo "Creating release schedule file..."
    echo ""
    echo "You need to populate this file with release dates from Confluence:"
    echo "https://confluence.internal.salesforce.com/spaces/RELEASE/pages/376178015/Release+Tracking"
    echo ""

    # Create initial schedule with 260.11 as example
    cat > "$SCHEDULE_FILE" << 'EOF'
{
  "260.11": {
    "start": "2026-04-24",
    "last_merge": "04/29",
    "sign_off": "05/05",
    "release": "2026-05-06"
  }
}
EOF

    echo "✓ Release schedule file created with example: $SCHEDULE_FILE"
    echo ""
    read -p "Do you want to edit it now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        vi "$SCHEDULE_FILE"
    fi
fi

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "Configuration files:"
echo "  - $CONFIG_FILE"
echo "  - $SCHEDULE_FILE"
echo ""
echo "You can now use the automation script:"
echo "  ./clone-epic-v2.sh <VERTICAL> <VERSION> Patch"
echo ""
echo "Example:"
echo "  ./clone-epic-v2.sh CME 260.11 Patch"
echo ""
