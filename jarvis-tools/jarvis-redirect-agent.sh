#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# jarvis-tools/jarvis-redirect-agent.sh
# JARVIS uses this to send a correction to a RUNNING agent.
# Cheaper than killing and re-spawning — no new API session needed.
# The message is typed directly into the agent's terminal via tmux.
#
# INPUT (pipe JSON via stdin):
# {
#   "task_id": "feat-custom-templates",
#   "message": "Stop. The schema is in src/types/template.ts. Use that."
# }
#
# OUTPUT (stdout, JSON):
# { "success": true,  "task_id": "...", "sent": "..." }
# { "success": false, "error": "..." }
#
# WHEN TO USE:
#   - Agent is going in the wrong direction
#   - Agent needs a file path or context you forgot to include
#   - Agent asked a question (via .openclaw/agent-question.txt)
#   - You want to add a constraint mid-task
# ══════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
REGISTRY="$REPO_ROOT/.openclaw/active-tasks.json"

# ── Read and validate JSON from stdin ─────────────────────────
INPUT=$(cat)
TASK_ID=$(echo "$INPUT" | jq -r '.task_id // empty')
MESSAGE=$(echo "$INPUT" | jq -r '.message  // empty')

if [[ -z "$TASK_ID" || -z "$MESSAGE" ]]; then
  jq -n '{"success": false, "error": "Both task_id and message are required"}'
  exit 1
fi

# ── Look up tmux session from registry ────────────────────────
TMUX_SESSION=$(jq -r --arg id "$TASK_ID" \
  '.[] | select(.id == $id) | .tmuxSession' "$REGISTRY")

if [[ -z "$TMUX_SESSION" || "$TMUX_SESSION" == "null" ]]; then
  jq -n --arg id "$TASK_ID" \
    '{"success": false, "error": ("Task not found in registry: " + $id)}'
  exit 1
fi

# ── Verify session is still alive ─────────────────────────────
if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  jq -n --arg s "$TMUX_SESSION" \
    '{"success": false, "error": ("tmux session is not running: " + $s + ". Use jarvis-create-task.sh to re-spawn.")}'
  exit 1
fi

# ── Send the message into the agent's terminal ────────────────
tmux send-keys -t "$TMUX_SESSION" "$MESSAGE" Enter

jq -n \
  --arg id      "$TASK_ID" \
  --arg session "$TMUX_SESSION" \
  --arg msg     "$MESSAGE" \
  '{"success": true, "task_id": $id, "session": $session, "sent": $msg}'
