#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# .openclaw/spawn-agent.sh
# Internal script — called by jarvis-tools/jarvis-create-task.sh
# Do NOT call this directly. Use jarvis-create-task.sh instead.
#
# Creates a git worktree, registers the task in active-tasks.json,
# and launches a Claude Code agent in an isolated tmux session.
#
# Usage:
#   .openclaw/spawn-agent.sh \
#     --id "feat-custom-templates" \
#     --branch "feat/custom-templates" \
#     --description "Save and reuse configurations" \
#     --prompt-file "/tmp/task-123.txt"
# ══════════════════════════════════════════════════════════════

set -euo pipefail

# ── Resolve REPO_ROOT robustly ────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"

# ── Config (override via env vars if needed) ──────────────────
WORKTREES_DIR="${WORKTREES_DIR:-$HOME/worktrees}"
USE_WORKTREE="${USE_WORKTREE:-true}"  # Set to "false" to work directly in REPO_ROOT
REGISTRY="$REPO_ROOT/.openclaw/active-tasks.json"
PROMPTS_DIR="$REPO_ROOT/.openclaw/prompts"
LOG_DIR="$REPO_ROOT/.openclaw/logs"
CLAUDE_MODEL="${CLAUDE_MODEL:-claude-opus-4-5}"
MAX_RETRIES=3
# ─────────────────────────────────────────────────────────────

# ── Parse arguments ───────────────────────────────────────────
TASK_ID="" BRANCH="" DESCRIPTION="" PROMPT_FILE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --id)           TASK_ID="$2";       shift 2 ;;
    --branch)       BRANCH="$2";        shift 2 ;;
    --description)  DESCRIPTION="$2";  shift 2 ;;
    --prompt-file)  PROMPT_FILE="$2";  shift 2 ;;
    *) echo "ERROR: Unknown argument: $1"; exit 1 ;;
  esac
done

# ── Validate ──────────────────────────────────────────────────
for var in TASK_ID BRANCH DESCRIPTION PROMPT_FILE; do
  [[ -z "${!var}" ]] && { echo "ERROR: --${var,,} is required"; exit 1; }
done
[[ ! -f "$PROMPT_FILE" ]] && { echo "ERROR: prompt file not found: $PROMPT_FILE"; exit 1; }

# ── Derived values ────────────────────────────────────────────
TMUX_SESSION="claude-$TASK_ID"
WORKTREE_PATH="$WORKTREES_DIR/$TASK_ID"
STARTED_AT=$(date +%s%3N)
mkdir -p "$PROMPTS_DIR" "$LOG_DIR" "$WORKTREES_DIR"

# Store the prompt permanently (needed for respawning)
SAVED_PROMPT="$PROMPTS_DIR/$TASK_ID.txt"
cp "$PROMPT_FILE" "$SAVED_PROMPT"
LOG_FILE="$LOG_DIR/$TASK_ID.log"

echo "🚀 Spawning agent: $TASK_ID"
echo "   Branch:  $BRANCH"
echo "   Model:   $CLAUDE_MODEL"
echo "   Worktree: $WORKTREE_PATH"

# ── 1. Setup: worktree or direct ───────────────────────────────
if [[ "$USE_WORKTREE" == "false" ]]; then
  # Work directly in REPO_ROOT (no worktree)
  AGENT_PATH="$REPO_ROOT"
  echo "🚀 Spawning agent: $TASK_ID"
  echo "   Branch:  $BRANCH (working directly in REPO_ROOT)"
  echo "   Model:   $CLAUDE_MODEL"
  echo "   Path:    $REPO_ROOT"
else
  # Create git worktree (isolated branch)
  AGENT_PATH="$WORKTREE_PATH"
  if [[ -d "$WORKTREE_PATH" ]]; then
    echo "⚠️  Worktree already exists — reusing: $WORKTREE_PATH"
  else
    # Detect default branch (main or master)
    DEFAULT_BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)
    git -C "$REPO_ROOT" worktree add "$WORKTREE_PATH" -b "$BRANCH" origin/$DEFAULT_BRANCH
    echo "✅ Worktree created."
  fi
fi

# ── 1b. Copy CLAUDE.md into agent path ────────────────────────
if [[ "$USE_WORKTREE" == "true" ]]; then
  TEMPLATE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  if [[ -f "$TEMPLATE_ROOT/CLAUDE.md" ]]; then
    cp "$TEMPLATE_ROOT/CLAUDE.md" "$WORKTREE_PATH/CLAUDE.md"
    echo "✅ CLAUDE.md copied into worktree."
  else
    echo "⚠️  CLAUDE.md not found in $TEMPLATE_ROOT — agent will have no instructions."
  fi
fi

# ── 2. Write a launch script for the agent ────────────────────
# IMPORTANT: We write the prompt to a file and source it from a
# launch script. This avoids ALL shell-quoting fragility for
# long, multi-line prompts. This is the correct approach.
LAUNCH_SCRIPT="$PROMPTS_DIR/$TASK_ID-launch.sh"
cat > "$LAUNCH_SCRIPT" << LAUNCH
#!/usr/bin/env bash
set -euo pipefail
cd "$AGENT_PATH"
PROMPT=\$(cat "$SAVED_PROMPT")
claude --model "$CLAUDE_MODEL" \\
  --dangerously-skip-permissions \\
  -p "\$PROMPT" \\
  2>&1 | tee "$LOG_FILE"
EXIT_CODE=\${PIPESTATUS[0]}
"$REPO_ROOT/.openclaw/complete-task.sh" --id "$TASK_ID" --exit-code "\$EXIT_CODE"
LAUNCH
chmod +x "$LAUNCH_SCRIPT"

# ── 3. Register task in JSON registry ─────────────────────────
TASK_JSON=$(jq -n \
  --arg id          "$TASK_ID" \
  --arg session     "$TMUX_SESSION" \
  --arg branch      "$BRANCH" \
  --arg desc        "$DESCRIPTION" \
  --arg agentPath   "$AGENT_PATH" \
  --arg prompt_file "$SAVED_PROMPT" \
  --argjson started "$STARTED_AT" \
  --argjson retries 0 \
  '{
    id:             $id,
    tmuxSession:    $session,
    branch:         $branch,
    description:    $desc,
    agentPath:      $agentPath,
    promptFile:     $prompt_file,
    startedAt:      $started,
    status:         "running",
    retries:        $retries,
    pr:             null,
    completedAt:    null,
    checks: {
      prCreated:           false,
      ciPassed:            false,
      claudeReviewPassed:  false,
      geminiReviewPassed:  false
    },
    note: ""
  }')

# Atomic update: remove any old entry with same id, append new one
TMPFILE=$(mktemp)
jq --argjson task "$TASK_JSON" \
  'map(select(.id != $task.id)) + [$task]' \
  "$REGISTRY" > "$TMPFILE" && mv "$TMPFILE" "$REGISTRY"

echo "📝 Task registered in registry."

# ── 4. Launch Claude Code in tmux ─────────────────────────────
# Kill any stale session with the same name first
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true

tmux new-session -d -s "$TMUX_SESSION" -c "$AGENT_PATH" "bash $LAUNCH_SCRIPT"

# ── 5. Confirm session is alive ───────────────────────────────
sleep 1
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "✅ Agent is running."
else
  echo "❌ tmux session failed to start. Check: $LOG_FILE"
  exit 1
fi

echo ""
echo "═══════════════════════════════════════════"
echo "  Task ID:       $TASK_ID"
echo "  tmux session:  $TMUX_SESSION"
echo "  Agent path:    $AGENT_PATH"
echo "  Log:           $LOG_FILE"
echo "  Monitor:       tmux attach -t $TMUX_SESSION"
echo "  Redirect:      tmux send-keys -t $TMUX_SESSION 'your message' Enter"
echo "═══════════════════════════════════════════"
