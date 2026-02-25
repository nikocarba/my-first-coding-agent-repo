#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# .openclaw/check-agents.sh
# Runs every 10 minutes via cron.
# Checks all running agents: are they alive? did CI finish?
# Does NOT call any AI API. 100% deterministic. Zero token cost.
# ══════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
REGISTRY="$REPO_ROOT/.openclaw/active-tasks.json"
NOTIFY_FILE="$REPO_ROOT/.openclaw/notifications.jsonl"
MAX_RETRIES=3

echo "$(date '+%Y-%m-%d %H:%M:%S') — check-agents.sh starting..."

# ── Read running tasks ─────────────────────────────────────────
# Use mapfile to avoid the empty-string edge case with while+herestring
mapfile -t RUNNING_TASKS < <(jq -c '.[] | select(.status == "running")' "$REGISTRY")

if [[ ${#RUNNING_TASKS[@]} -eq 0 ]]; then
  echo "  No running tasks. Exiting."
  exit 0
fi

echo "  Found ${#RUNNING_TASKS[@]} running task(s)."

for task in "${RUNNING_TASKS[@]}"; do
  TASK_ID=$(echo "$task" | jq -r '.id')
  TMUX_SESSION=$(echo "$task" | jq -r '.tmuxSession')
  RETRIES=$(echo "$task" | jq -r '.retries')
  BRANCH=$(echo "$task" | jq -r '.branch')

  echo ""
  echo "  ── Task: $TASK_ID ──"

  # ── 1. Is the tmux session still alive? ───────────────────
  if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "  ⚠️  tmux session '$TMUX_SESSION' is dead."

    if [[ "$RETRIES" -ge "$MAX_RETRIES" ]]; then
      echo "  ❌ Max retries ($MAX_RETRIES) reached. Marking as failed."

      TMPFILE=$(mktemp)
      jq --arg id "$TASK_ID" \
         'map(if .id == $id then . + {
            status: "failed",
            note:   "Max retries reached. Human attention required."
          } else . end)' \
         "$REGISTRY" > "$TMPFILE" && mv "$TMPFILE" "$REGISTRY"

      jq -n \
        --arg id   "$TASK_ID" \
        --argjson ts "$(date +%s%3N)" \
        '{ task_id: $id, status: "failed",
           note: "Max retries reached. Human attention required.",
           pr: null, timestamp: $ts }' \
        >> "$NOTIFY_FILE"

    else
      NEW_RETRIES=$((RETRIES + 1))
      echo "  🔄 Signaling JARVIS to re-examine and re-spawn (attempt $NEW_RETRIES/$MAX_RETRIES)..."

      TMPFILE=$(mktemp)
      jq --arg id "$TASK_ID" --argjson r "$NEW_RETRIES" \
         'map(if .id == $id then . + {
            retries: $r,
            note:    "tmux session died. Waiting for JARVIS to re-spawn."
          } else . end)' \
         "$REGISTRY" > "$TMPFILE" && mv "$TMPFILE" "$REGISTRY"

      # Signal JARVIS — JARVIS will read the log, diagnose, and re-spawn
      jq -n \
        --arg id "$TASK_ID" \
        --argjson ts "$(date +%s%3N)" \
        '{ task_id: $id, status: "needs_respawn",
           note: "tmux session died. JARVIS should read the log and re-spawn with an improved prompt.",
           pr: null, timestamp: $ts }' \
        >> "$NOTIFY_FILE"
    fi
    continue
  fi

  echo "  ✅ tmux session alive."

  # ── 2. Check PR and CI status ──────────────────────────────
  PR_NUMBER=$(gh pr list --head "$BRANCH" --json number \
    --jq '.[0].number // empty' 2>/dev/null || true)

  if [[ -z "$PR_NUMBER" ]]; then
    echo "  🔨 No PR yet — agent still working."
    continue
  fi

  echo "  📋 PR #$PR_NUMBER found. Checking CI..."

  # Check if all CI checks have completed
  CI_CHECKS=$(gh pr checks "$PR_NUMBER" --json name,state 2>/dev/null || echo "[]")
  TOTAL=$(echo "$CI_CHECKS" | jq 'length')
  COMPLETED=$(echo "$CI_CHECKS" | jq '[.[] | select(.state != "PENDING" and .state != "IN_PROGRESS")] | length')

  if [[ "$TOTAL" -eq 0 ]]; then
    echo "  ⏳ No CI checks registered yet."
  elif [[ "$COMPLETED" -lt "$TOTAL" ]]; then
    echo "  ⏳ CI running ($COMPLETED/$TOTAL checks complete)."
  else
    echo "  ✅ All CI checks complete. Running complete-task.sh..."
    "$REPO_ROOT/.openclaw/complete-task.sh" --id "$TASK_ID" --exit-code 0
  fi
done

echo ""
echo "$(date '+%Y-%m-%d %H:%M:%S') — check-agents.sh done."
