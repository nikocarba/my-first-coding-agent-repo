# JARVIS-MISSION.md
# ══════════════════════════════════════════════════════════════
# DIRECT INSTRUCTIONS FOR JARVIS (minimax M2.5 orchestrator)
#
# You are JARVIS. This document tells you exactly what to do
# to install OpenClaw — a system that lets you spawn and manage
# Claude Code coding agents at zero communication cost.
#
# Read this entire file first, then execute each phase in order.
# Do not skip phases. Do not ask for permission between steps.
# ══════════════════════════════════════════════════════════════

## WHAT YOU ARE BUILDING

A two-tier agent system:
- YOU (JARVIS) = orchestrator. You have business context, memory,
  meeting notes, customer info. You spawn tasks and supervise agents.
- CODE AGENTS = coders. They only know what you tell them.
  They implement, test, and open PRs. They know nothing else.

Communication between you and the agents is FILE-BASED (zero API cost):
- You → Agent: write a prompt file, call jarvis-create-task.sh
- Agent → You: agent appends one line to notifications.jsonl
- You read it by calling jarvis-poll-notifications.sh

## PHASE 0 — VERIFY DEPENDENCIES

Before doing anything, run these commands and confirm all pass.
If any fail, install the missing tool before continuing.

```bash
# Required tools — verify each one:
git --version          # Must be >= 2.20 (for worktree support)
tmux -V                # Must be installed
jq --version           # Must be >= 1.6
gh --version           # GitHub CLI — must be installed AND authenticated
claude --version       # Claude Code CLI — must be installed
pnpm --version || npm --version   # At least one package manager

# Verify gh is authenticated (must show your username, not an error):
gh auth status
```

If `gh` is not authenticated, run: `gh auth login`
If `claude` CLI is not installed, follow: https://docs.claude.ai/claude-code

## PHASE 1 — IDENTIFY YOUR REPO ROOT

You must know the absolute path to the git repository you will be managing.
Run this and save the output — you will use it everywhere as REPO_ROOT:

```bash
# Run this from inside your target repository:
git rev-parse --show-toplevel
# Example output: /Users/yourname/projects/myapp
# Save this value. It is your REPO_ROOT.
```

## PHASE 2 — INSTALL OPENCLAW FILES

Copy the OpenClaw files into your repository. All paths below are
relative to REPO_ROOT. Run these commands from inside REPO_ROOT:

```bash
# 1. Create the directory structure
mkdir -p .openclaw/logs .openclaw/prompts jarvis-tools

# 2. Copy all files from this package into your repo.
#    If you received this as a folder, copy each file:
#    - JARVIS-MISSION.md          → REPO_ROOT/JARVIS-MISSION.md
#    - CLAUDE.md                  → REPO_ROOT/CLAUDE.md
#    - .openclaw/spawn-agent.sh   → REPO_ROOT/.openclaw/spawn-agent.sh
#    - .openclaw/complete-task.sh → REPO_ROOT/.openclaw/complete-task.sh
#    - .openclaw/check-agents.sh  → REPO_ROOT/.openclaw/check-agents.sh
#    - .openclaw/cleanup.sh       → REPO_ROOT/.openclaw/cleanup.sh
#    - jarvis-tools/jarvis-create-task.sh
#    - jarvis-tools/jarvis-poll-notifications.sh
#    - jarvis-tools/jarvis-redirect-agent.sh
#    - jarvis-tools/JARVIS-SYSTEM-PROMPT.md

# 3. Make all scripts executable
chmod +x .openclaw/*.sh jarvis-tools/*.sh

# 4. Initialize the task registry and notification queue
echo '[]' > .openclaw/active-tasks.json
touch .openclaw/notifications.jsonl
touch .openclaw/.notification-cursor
```

## PHASE 3 — RUN SETUP.SH

```bash
# From REPO_ROOT, run:
bash setup.sh
```

setup.sh will:
- Confirm all files are in place
- Set REPO_ROOT inside every script automatically
- Report any missing files or permissions errors
- Print the exact cron commands you need for Phase 4

## PHASE 4 — INSTALL CRON JOBS

setup.sh (Phase 3) will print two cron commands. Install them:

```bash
# Open crontab editor:
crontab -e

# Add these two lines (setup.sh prints the exact paths):
*/10 * * * * REPO_ROOT=/YOUR/REPO/PATH /YOUR/REPO/PATH/.openclaw/check-agents.sh >> /YOUR/REPO/PATH/.openclaw/logs/cron.log 2>&1
0 2 * * * REPO_ROOT=/YOUR/REPO/PATH /YOUR/REPO/PATH/.openclaw/cleanup.sh >> /YOUR/REPO/PATH/.openclaw/logs/cleanup.log 2>&1

# Verify cron was saved:
crontab -l
```

## PHASE 5 — UPDATE YOUR OWN SYSTEM PROMPT

Read the file at: jarvis-tools/JARVIS-SYSTEM-PROMPT.md

That file contains a block of text you must add to YOUR OWN system prompt
in your OpenClaw / minimax M2.5 configuration. This teaches you (JARVIS)
how to use your tools.

Add it to your system prompt now. After adding it, you will know:
- How to create a coding task (jarvis-create-task.sh)
- How to check for completed tasks (jarvis-poll-notifications.sh)
- How to redirect a stuck agent (jarvis-redirect-agent.sh)
- How to read agent logs when debugging

## PHASE 6 — UPDATE .gitignore

Add these lines to your repo's .gitignore to avoid committing runtime state:

```bash
cat >> .gitignore << 'EOF'

# OpenClaw runtime state (do not commit)
.openclaw/active-tasks.json
.openclaw/notifications.jsonl
.openclaw/.notification-cursor
.openclaw/logs/
.openclaw/prompts/
.openclaw/archive-*.json
EOF
```

## PHASE 7 — SMOKE TEST

Run this test to confirm the full pipeline works end-to-end.
This spawns a real Claude Code agent on a test branch.

```bash
# From REPO_ROOT:
echo '{
  "id": "smoke-test",
  "branch": "feat/smoke-test",
  "description": "Smoke test: verify OpenClaw is working",
  "prompt": "Create a file called OPENCLAW-TEST.md at the repo root. Write in it: \"OpenClaw smoke test passed on $(date).\". Then commit it, push the branch, and open a PR with title \"chore: OpenClaw smoke test\". This is a test — do exactly this and nothing else."
}' | jarvis-tools/jarvis-create-task.sh

# Monitor the agent:
# (replace 'smoke-test' with the session name printed above)
tmux attach -t claude-smoke-test

# After a few minutes, check for the completion notification:
jarvis-tools/jarvis-poll-notifications.sh

# Expected output: JSON with status "done" or "needs_review"
```

If the smoke test passes, OpenClaw is fully operational.

## PHASE 8 — CONFIRM COMPLETION

After all phases complete, report back with:
1. ✅ or ❌ for each phase
2. The REPO_ROOT path you used
3. Output of: `crontab -l | grep openclaw`
4. Output of: `cat .openclaw/active-tasks.json`
5. Any errors encountered

## TROUBLESHOOTING

**`gh: command not found`**
Install GitHub CLI: https://cli.github.com

**`claude: command not found`**
Install Claude Code CLI: https://docs.claude.ai/claude-code
Then run: `claude --version` to confirm.

**tmux session dies immediately**
Check the log: `cat .openclaw/logs/smoke-test.log`
Common cause: Claude Code not authenticated. Run `claude auth` first.

**`git worktree add` fails**
Confirm you are in a git repo with a remote named `origin` and a `main` branch.
Check: `git remote -v` and `git branch -a`

**Notifications file is empty after smoke test**
The agent may still be running. Wait 5 minutes and poll again.
Or check if tmux session is alive: `tmux ls`
