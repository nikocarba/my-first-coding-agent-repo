#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# .openclaw/cleanup.sh
# Runs daily at 2am via cron.
# Removes worktrees, branches, and tmux sessions for finished tasks.
# Archives completed tasks and keeps active-tasks.json lean.
# ══════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
REGISTRY="$REPO_ROOT/.openclaw/active-tasks.json"
WORKTREES_DIR="${WORKTREES_DIR:-$HOME/worktrees}"

echo "$(date '+%Y-%m-%d %H:%M:%S') — cleanup.sh starting..."

# ── Collect finished tasks ─────────────────────────────────────
mapfile -t FINISHED_TASKS < <(
  jq -c '.[] | select(.status == "done" or .status == "failed")' "$REGISTRY"
)

if [[ ${#FINISHED_TASKS[@]} -eq 0 ]]; then
  echo "  Nothing to clean up."
else
  echo "  Cleaning up ${#FINISHED_TASKS[@]} finished task(s)..."

  for task in "${FINISHED_TASKS[@]}"; do
    TASK_ID=$(echo "$task" | jq -r '.id')
    WORKTREE=$(echo "$task" | jq -r '.worktree')
    BRANCH=$(echo "$task" | jq -r '.branch')
    TMUX_SESSION=$(echo "$task" | jq -r '.tmuxSession')

    echo "  ── $TASK_ID ──"

    # Remove git worktree
    if [[ -d "$WORKTREE" ]]; then
      git -C "$REPO_ROOT" worktree remove "$WORKTREE" --force 2>/dev/null \
        || rm -rf "$WORKTREE"
      echo "    ✅ Removed worktree: $WORKTREE"
    fi

    # Delete local branch (remote branch stays until PR is merged/closed)
    git -C "$REPO_ROOT" branch -D "$BRANCH" 2>/dev/null \
      && echo "    ✅ Deleted branch: $BRANCH" || true

    # Kill tmux session (probably already dead, but clean up if not)
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null \
      && echo "    ✅ Killed tmux: $TMUX_SESSION" || true

    # Remove the per-task launch script (prompts are kept for audit)
    LAUNCH="$REPO_ROOT/.openclaw/prompts/$TASK_ID-launch.sh"
    [[ -f "$LAUNCH" ]] && rm "$LAUNCH" && echo "    ✅ Removed launch script."
  done
fi

# ── Archive finished tasks ─────────────────────────────────────
ARCHIVE_FILE="$REPO_ROOT/.openclaw/archive-$(date +%Y-%m).jsonl"
jq -c '.[] | select(.status == "done" or .status == "failed")' "$REGISTRY" \
  >> "$ARCHIVE_FILE"
echo "  📦 Archived to: $ARCHIVE_FILE"

# ── Prune registry to active-only ─────────────────────────────
TMPFILE=$(mktemp)
jq '[.[] | select(.status == "running" or .status == "needs_review" or .status == "needs_respawn")]' \
  "$REGISTRY" > "$TMPFILE" && mv "$TMPFILE" "$REGISTRY"

REMAINING=$(jq 'length' "$REGISTRY")
echo "  📋 Registry pruned. $REMAINING active task(s) remain."
echo "$(date '+%Y-%m-%d %H:%M:%S') — cleanup.sh done."
