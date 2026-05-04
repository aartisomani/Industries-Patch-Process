#!/bin/bash
# Post Slack notifications for package drops
# Usage: ./post-slack-notifications.sh <messages_file>

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <messages_file>"
    exit 1
fi

MESSAGES_FILE="$1"

if [ ! -f "$MESSAGES_FILE" ]; then
    echo "Error: Messages file not found: $MESSAGES_FILE"
    exit 1
fi

echo "This script requires Claude Code interactive session to post to Slack"
echo "Please ask Claude to post these messages using the Slack MCP tool"
echo ""
echo "Messages file: $MESSAGES_FILE"
echo ""
cat "$MESSAGES_FILE"
