#!/bin/bash

# SideQuest IPC Socket Helper
# Sends quest trigger to native app via Unix domain socket
# Called by: plugin/hooks/stop-hook
# Args: quest_id tracking_id
# Exit: Always 0 (silent failure on any error)

QUEST_ID="$1"
TRACKING_ID="$2"
SOCKET_PATH="/tmp/sidequest.sock"

# Validate arguments
if [ -z "$QUEST_ID" ] || [ -z "$TRACKING_ID" ]; then
  exit 0  # Missing args, silently skip
fi

# Check if socket exists (app is running)
if [ ! -S "$SOCKET_PATH" ]; then
  exit 0  # App not running, silently skip
fi

# Create JSON payload
PAYLOAD="{\"questId\":\"${QUEST_ID}\",\"trackingId\":\"${TRACKING_ID}\"}"

# Send via socket with 500ms timeout
# Using 'timeout' command for reliability across macOS versions
{
  echo -n "$PAYLOAD"
} | timeout 0.5 nc -U "$SOCKET_PATH" 2>/dev/null

# Always exit 0, even if nc fails
exit 0
