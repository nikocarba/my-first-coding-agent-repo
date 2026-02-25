#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# jarvis-tools/jarvis-poll-notifications.sh
# JARVIS calls this to get new task completion events.
# Returns only UNREAD notifications since last call.
# Marks them as read automatically (cursor-based).
#
# OUTPUT (stdout, JSON array):
# []                                  ← nothing new
# [{"task_id":"...", "status":"done", "pr":341, "note":"...", "timestamp":...}]
#
# STATUS VALUES:
#   "done"          → PR ready to merge, all checks passed
#   "needs_review"  → PR open, but some checks pending/failed
#   "needs_respawn" → Agent died, JARVIS should diagnose and re-spawn
#   "failed"        → Max retries exceeded, human attention needed
#
# JARVIS SHOULD:
#   • Call this after every user interaction
#   • Call this proactively in the monitoring loop
#   • On "needs_respawn": read the log, diagnose, re-spawn with better prompt
#   • On "done": notify the human (Telegram, etc.)
# ══════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
NOTIFY_FILE="$REPO_ROOT/.openclaw/notifications.jsonl"
CURSOR_FILE="$REPO_ROOT/.openclaw/.notification-cursor"

# No notifications file yet → nothing to report
if [[ ! -f "$NOTIFY_FILE" ]]; then
  echo "[]"
  exit 0
fi

# Read cursor (how many lines JARVIS has already seen)
CURSOR=0
if [[ -f "$CURSOR_FILE" ]]; then
  CURSOR=$(cat "$CURSOR_FILE")
  # Validate it's a number
  [[ "$CURSOR" =~ ^[0-9]+$ ]] || CURSOR=0
fi

# Count total lines (handle empty file)
TOTAL=$(wc -l < "$NOTIFY_FILE" | tr -d ' ')
TOTAL="${TOTAL:-0}"

if [[ "$CURSOR" -ge "$TOTAL" ]]; then
  echo "[]"
  exit 0
fi

# Read only new lines since cursor
NEW_LINES=$(tail -n +"$((CURSOR + 1))" "$NOTIFY_FILE")

# Advance cursor
echo "$TOTAL" > "$CURSOR_FILE"

# Output as JSON array (each line is valid JSON)
echo "$NEW_LINES" | jq -s '.'
