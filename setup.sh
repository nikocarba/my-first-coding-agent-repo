#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# setup.sh
# Run this from your target repo root after copying the OpenClaw files.
# It verifies dependencies, sets paths, and prints the cron commands.
#
# Usage:
#   cd /path/to/your/repo
#   bash /path/to/openclaw/setup.sh
#
# Or if you copied OpenClaw into the repo already:
#   bash setup.sh
# ══════════════════════════════════════════════════════════════

set -euo pipefail

# ── Resolve REPO_ROOT ─────────────────────────────────────────
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "❌ ERROR: Not inside a git repository. Run this from your project root."
  exit 1
}

OPENCLAW="$REPO_ROOT/.openclaw"
JARVIS_TOOLS="$REPO_ROOT/jarvis-tools"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║         OpenClaw Setup — JARVIS Edition              ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  REPO_ROOT: $REPO_ROOT"
echo ""

ERRORS=0

# ══════════════════════════════════════════════════════════════
# PHASE 1 — Check dependencies
# ══════════════════════════════════════════════════════════════
echo "── Phase 1: Checking dependencies ──────────────────────"

check_dep() {
  local cmd="$1" hint="${2:-}"
  if command -v "$cmd" &>/dev/null; then
    echo "  ✅ $cmd found: $(command -v "$cmd")"
  else
    echo "  ❌ $cmd NOT FOUND. ${hint}"
    ERRORS=$((ERRORS + 1))
  fi
}

check_dep git
check_dep tmux   "Install via: brew install tmux (Mac) or apt install tmux (Linux)"
check_dep jq     "Install via: brew install jq (Mac) or apt install jq (Linux)"
check_dep gh     "Install via: https://cli.github.com — then run: gh auth login"
check_dep claude "Install Claude Code CLI: https://docs.claude.ai/claude-code"

# Check gh auth
if command -v gh &>/dev/null; then
  if gh auth status &>/dev/null; then
    echo "  ✅ gh is authenticated"
  else
    echo "  ❌ gh is NOT authenticated. Run: gh auth login"
    ERRORS=$((ERRORS + 1))
  fi
fi

if [[ $ERRORS -gt 0 ]]; then
  echo ""
  echo "  ❌ $ERRORS dependency issue(s) found. Fix them before continuing."
  exit 1
fi
echo ""

# ══════════════════════════════════════════════════════════════
# PHASE 2 — Verify files are in place
# ══════════════════════════════════════════════════════════════
echo "── Phase 2: Verifying files ─────────────────────────────"

REQUIRED_FILES=(
  ".openclaw/spawn-agent.sh"
  ".openclaw/complete-task.sh"
  ".openclaw/check-agents.sh"
  ".openclaw/cleanup.sh"
  "jarvis-tools/jarvis-create-task.sh"
  "jarvis-tools/jarvis-poll-notifications.sh"
  "jarvis-tools/jarvis-redirect-agent.sh"
  "jarvis-tools/JARVIS-SYSTEM-PROMPT.md"
  "AGENTS.md"
)

for f in "${REQUIRED_FILES[@]}"; do
  if [[ -f "$REPO_ROOT/$f" ]]; then
    echo "  ✅ $f"
  else
    echo "  ❌ MISSING: $f"
    ERRORS=$((ERRORS + 1))
  fi
done

if [[ $ERRORS -gt 0 ]]; then
  echo ""
  echo "  ❌ $ERRORS file(s) missing. Copy all OpenClaw files into the repo first."
  exit 1
fi
echo ""

# ══════════════════════════════════════════════════════════════
# PHASE 3 — Set permissions
# ══════════════════════════════════════════════════════════════
echo "── Phase 3: Setting permissions ─────────────────────────"
chmod +x "$OPENCLAW"/*.sh "$JARVIS_TOOLS"/*.sh
echo "  ✅ All scripts are executable."
echo ""

# ══════════════════════════════════════════════════════════════
# PHASE 4 — Initialize runtime files
# ══════════════════════════════════════════════════════════════
echo "── Phase 4: Initializing runtime files ──────────────────"

mkdir -p "$OPENCLAW/logs" "$OPENCLAW/prompts"

[[ ! -f "$OPENCLAW/active-tasks.json" ]] && \
  echo '[]' > "$OPENCLAW/active-tasks.json" && echo "  ✅ Created active-tasks.json"
[[ -f "$OPENCLAW/active-tasks.json" ]] && \
  echo "  ✅ active-tasks.json exists"

touch "$OPENCLAW/notifications.jsonl"
touch "$OPENCLAW/.notification-cursor"
echo "  ✅ Notification queue initialized."
echo ""

# ══════════════════════════════════════════════════════════════
# PHASE 5 — Patch REPO_ROOT into all scripts
# ══════════════════════════════════════════════════════════════
echo "── Phase 5: Patching REPO_ROOT into scripts ─────────────"

# Patch JARVIS-SYSTEM-PROMPT.md (replace the placeholder)
SYSTEM_PROMPT="$JARVIS_TOOLS/JARVIS-SYSTEM-PROMPT.md"
if grep -q "REPO_ROOT_PLACEHOLDER" "$SYSTEM_PROMPT"; then
  # Use a temp file to avoid in-place sed portability issues (Mac vs Linux)
  TMPFILE=$(mktemp)
  sed "s|REPO_ROOT_PLACEHOLDER|$REPO_ROOT|g" "$SYSTEM_PROMPT" > "$TMPFILE"
  mv "$TMPFILE" "$SYSTEM_PROMPT"
  echo "  ✅ Patched JARVIS-SYSTEM-PROMPT.md with: $REPO_ROOT"
else
  echo "  ℹ️  JARVIS-SYSTEM-PROMPT.md already patched."
fi
echo ""

# ══════════════════════════════════════════════════════════════
# PHASE 6 — Update .gitignore
# ══════════════════════════════════════════════════════════════
echo "── Phase 6: Updating .gitignore ─────────────────────────"
GITIGNORE="$REPO_ROOT/.gitignore"
MARKER="# OpenClaw runtime state"

if [[ -f "$GITIGNORE" ]] && grep -q "$MARKER" "$GITIGNORE"; then
  echo "  ℹ️  .gitignore already has OpenClaw entries."
else
  cat >> "$GITIGNORE" << 'EOF'

# OpenClaw runtime state (do not commit)
.openclaw/active-tasks.json
.openclaw/notifications.jsonl
.openclaw/.notification-cursor
.openclaw/logs/
.openclaw/prompts/
.openclaw/archive-*.json
EOF
  echo "  ✅ Added OpenClaw entries to .gitignore"
fi
echo ""

# ══════════════════════════════════════════════════════════════
# DONE — Print cron commands and next steps
# ══════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✅  Setup complete!                                 ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "── NEXT STEP 1: Install cron jobs ──────────────────────"
echo "  Run: crontab -e"
echo "  Add these two lines:"
echo ""
echo "  */10 * * * * REPO_ROOT=$REPO_ROOT $OPENCLAW/check-agents.sh >> $OPENCLAW/logs/cron.log 2>&1"
echo "  0 2 * * * REPO_ROOT=$REPO_ROOT $OPENCLAW/cleanup.sh >> $OPENCLAW/logs/cleanup.log 2>&1"
echo ""
echo "── NEXT STEP 2: Update JARVIS system prompt ─────────────"
echo "  Read: $JARVIS_TOOLS/JARVIS-SYSTEM-PROMPT.md"
echo "  Add its contents to your JARVIS system prompt in OpenClaw."
echo "  (The file has already been patched with your repo path.)"
echo ""
echo "── NEXT STEP 3: Run the smoke test ──────────────────────"
echo "  echo '{"
echo "    \"id\": \"smoke-test\","
echo "    \"branch\": \"feat/smoke-test\","
echo "    \"description\": \"Verify OpenClaw works end to end\","
echo "    \"prompt\": \"Create OPENCLAW-TEST.md with todays date. Commit, push, open PR.\""
echo "  }' | $JARVIS_TOOLS/jarvis-create-task.sh"
echo ""
