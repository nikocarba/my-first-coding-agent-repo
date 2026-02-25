#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# jarvis-tools/jarvis-create-task.sh
# THE PRIMARY TOOL JARVIS USES to spawn a Claude Code agent.
#
# Reads a JSON payload from stdin. Validates it, writes the
# prompt to a temp file, and delegates to .openclaw/spawn-agent.sh
#
# INPUT (pipe JSON via stdin):
# {
#   "id":          "feat-custom-templates",      ← kebab-case, unique
#   "branch":      "feat/custom-templates",      ← git branch name
#   "description": "One sentence summary",
#   "prompt":      "Full detailed task prompt for Claude Code..."
# }
#
# OUTPUT (stdout, JSON):
# { "success": true,  "task_id": "feat-custom-templates", "message": "..." }
# { "success": false, "error": "..." }
#
# EXAMPLE:
#   echo '{"id":"fix-login","branch":"fix/login-bug","description":"Fix login","prompt":"..."}' \
#     | jarvis-tools/jarvis-create-task.sh
# ══════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"

# ── Read and validate JSON from stdin ─────────────────────────
if ! INPUT=$(cat); then
  jq -n '{"success": false, "error": "Failed to read stdin"}'
  exit 1
fi

# Validate JSON
if ! echo "$INPUT" | jq empty 2>/dev/null; then
  jq -n '{"success": false, "error": "Invalid JSON on stdin"}'
  exit 1
fi

TASK_ID=$(echo "$INPUT"    | jq -r '.id           // empty')
BRANCH=$(echo "$INPUT"     | jq -r '.branch       // empty')
DESCRIPTION=$(echo "$INPUT" | jq -r '.description // empty')
PROMPT=$(echo "$INPUT"     | jq -r '.prompt       // empty')

# Check all fields are present
MISSING=""
[[ -z "$TASK_ID"     ]] && MISSING="$MISSING id"
[[ -z "$BRANCH"      ]] && MISSING="$MISSING branch"
[[ -z "$DESCRIPTION" ]] && MISSING="$MISSING description"
[[ -z "$PROMPT"      ]] && MISSING="$MISSING prompt"

if [[ -n "$MISSING" ]]; then
  jq -n --arg m "$MISSING" '{"success": false, "error": ("Missing required fields:" + $m)}'
  exit 1
fi

# ── Enforce single-agent limit ────────────────────────────────
RUNNING_COUNT=$(jq '[.[] | select(.status == "running")] | length' "$REGISTRY")
if [[ "$RUNNING_COUNT" -gt 0 ]]; then
  RUNNING_ID=$(jq -r '[.[] | select(.status == "running")] | .[0].id' "$REGISTRY")
  jq -n --arg id "$RUNNING_ID" \
    '{"success": false, "error": ("An agent is already running: " + $id + ". JARVIS must wait for it to finish before spawning a new one.")}'
  exit 1
fi

# ── Check for duplicate task ID ───────────────────────────────
REGISTRY="$REPO_ROOT/.openclaw/active-tasks.json"
EXISTING_STATUS=$(jq -r --arg id "$TASK_ID" \
  '.[] | select(.id == $id) | .status' "$REGISTRY" 2>/dev/null || true)

if [[ "$EXISTING_STATUS" == "running" ]]; then
  jq -n --arg id "$TASK_ID" \
    '{"success": false, "error": ("Task " + $id + " is already running. Use jarvis-redirect-agent.sh to send it a message, or wait for it to finish.")}'
  exit 1
fi

# ── Write prompt to temp file (avoids all shell-quoting issues) ──
PROMPT_FILE=$(mktemp /tmp/jarvis-prompt-XXXXXX.txt)
echo "$PROMPT" > "$PROMPT_FILE"

# ── Delegate to spawn-agent.sh ────────────────────────────────
if SPAWN_OUTPUT=$(
  "$REPO_ROOT/.openclaw/spawn-agent.sh" \
    --id "$TASK_ID" \
    --branch "$BRANCH" \
    --description "$DESCRIPTION" \
    --prompt-file "$PROMPT_FILE" 2>&1
); then
  rm -f "$PROMPT_FILE"
  jq -n \
    --arg id   "$TASK_ID" \
    --arg desc "$DESCRIPTION" \
    --arg out  "$SPAWN_OUTPUT" \
    '{"success": true, "task_id": $id, "message": ("Agent spawned: " + $desc), "detail": $out}'
else
  EXIT=$?
  rm -f "$PROMPT_FILE"
  jq -n \
    --arg id  "$TASK_ID" \
    --arg out "$SPAWN_OUTPUT" \
    --argjson code "$EXIT" \
    '{"success": false, "task_id": $id, "error": "spawn-agent.sh failed", "detail": $out, "exit_code": $code}'
  exit 1
fi
