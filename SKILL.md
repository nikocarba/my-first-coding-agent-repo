---
name: custom-coding-agent
description: "Spawn and manage Claude Code coding agents via shell scripts in the jarvis-tools repo. Use when you need to: create new complex coding tasks (features, bug fixes, refactors), poll for completed agent work, redirect a running agent mid-task, diagnose failed or stuck agents, check agent logs, or answer agent questions. Also use when Sentry errors need fixing or feature requests from meeting notes need implementation. Use the prompt-writing guide in this skill when crafting agent prompts."
---

# Coding Agent

You spawn and manage Claude Code agents through shell scripts. Communication is
file-based (zero API cost). The only API costs are your own reasoning + Claude Code's coding.

REPO_ROOT="<TARGET_REPO_PATH>"   # Set to the repo you are managing — NEVER this template repo

---

## Tools

### TOOL 1 — Spawn a new coding task

```bash
echo '<JSON>' | ${REPO_ROOT}/jarvis-tools/jarvis-create-task.sh
```

Input schema:

```json
{
  "id":          "feat-custom-templates",
  "branch":      "feat/custom-templates",
  "description": "One sentence: what this task does",
  "prompt":      "FULL detailed prompt for Claude Code. See prompt guide below."
}
```

Output: `{"success": true, "task_id": "...", "message": "..."}` or error JSON.

**ID naming rules:** kebab-case, unique, short. Examples: `fix-login-bug`, `feat-csv-export`, `chore-update-deps`

### TOOL 2 — Poll for completed tasks

```bash
${REPO_ROOT}/jarvis-tools/jarvis-poll-notifications.sh
```

Returns a JSON array of new events since you last polled. Always `[]` if nothing new.

```json
[
  {
    "task_id":   "feat-custom-templates",
    "status":    "done",
    "note":      "All checks passed. Ready to merge.",
    "pr":        341,
    "timestamp": 1740275400000
  }
]
```

**Status values and your action:**

- **done** — PR open, all CI + reviews passed → Notify human to merge
- **needs_review** — PR open, checks still running → Wait and poll again
- **needs_respawn** — Agent died → Read log, diagnose, re-spawn with better prompt
- **failed** — Max retries exceeded → Alert human for manual intervention

### TOOL 3 — Redirect a running agent mid-task

```bash
echo '{"task_id":"feat-custom-templates","message":"Stop. Focus on the API layer first."}' \
  | ${REPO_ROOT}/jarvis-tools/jarvis-redirect-agent.sh
```

Use this when:

- Agent is going in the wrong direction
- Agent needs context you forgot to include
- Agent asked a question via `.openclaw/agent-question.txt`

### TOOL 4 — Read full task registry

```bash
cat ${REPO_ROOT}/.openclaw/active-tasks.json | jq '.'
```

### TOOL 5 — Read agent log (diagnose failed/stuck agents)

```bash
tail -100 ${REPO_ROOT}/.openclaw/logs/<task_id>.log
```

### TOOL 6 — Check for agent questions

```bash
cat ${REPO_ROOT}/.openclaw/agent-question.txt 2>/dev/null || echo "(no questions)"
```

If a question exists, answer it with TOOL 3, then clear the file:

```bash
rm ${REPO_ROOT}/.openclaw/agent-question.txt
```

---

## Proactive Monitoring Loop

Run these checks every 10 minutes (system cron triggers you):

1. `jarvis-poll-notifications.sh` → handle any completed/failed tasks
2. Check Sentry for new errors → spawn fix agents
3. Check meeting notes / Obsidian vault → flag customer requests → spawn feature agents
4. Check `agent-question.txt` → answer any agent questions
5. Check running tasks → redirect any that seem stuck (read logs)

---

## Agent Selection Guide

- **Backend logic, complex bugs, multi-file refactors** → Claude Code
- **Frontend component work** → Claude Code
- **Git operations (changelog, docs)** → Claude Code
- **UI design spec (generate HTML/CSS first)** → Gemini → then Claude Code to implement

You spawn all agents. You route work between them. You are the only one with full context.

---

## How to Write Excellent Agent Prompts

A Claude Code agent has NO business context. Write as if briefing a contractor
who is smart but knows nothing about your customers or codebase conventions.

**Always include:**

1. What to build or fix (be specific)
2. Which files/types are relevant: `src/types/X.ts`, `src/components/Y.tsx`
3. The customer/business reason (one sentence — helps agent prioritize edge cases)
4. Edge cases to handle
5. How to test it manually
6. What "done" looks like (PR description template helps)

**Bad prompt (too vague):**

> "Add a template system so customers can reuse configurations."

**Good prompt:**

> "Build a template system for email configurations. Relevant files:
> `src/types/EmailConfig.ts` (the config schema), `src/components/ConfigEditor.tsx`
> (where save/load UI should appear), `src/api/templates.ts` (create this file).
>
> Customer context: Agency customers want to save their config, name it, and
> apply it across team members. This is their top support request.
>
> Implementation: Add `POST /api/templates` (save), `GET /api/templates` (list),
> `POST /api/templates/:id/apply` (apply to current config). Store in DB table
> `email_templates` (schema in `prisma/schema.prisma`).
>
> Edge cases: name conflicts (return 409), max 50 templates per org, handle
> configs with custom fields not in the template.
>
> Tests: add unit tests in `src/api/templates.test.ts`.
>
> When done: create PR with screenshot of the save/load UI in ConfigEditor."

---

## Deploying Agents on a Target Repo

**All agents run on a separate target repo — NEVER on this template repo.**
This repo is your toolbox. The target repo is the codebase agents write code in.

`REPO_ROOT` (set above) must point to the target repo. When you spawn a task,
`spawn-agent.sh` automatically:

1. Creates a git worktree from `origin/main` of the target repo
2. Copies `CLAUDE.md` from this template repo into the worktree

This means agents always get the latest `CLAUDE.md` instructions, even though
the file lives here — not in the target repo. No manual copy step is needed.

**If you update `CLAUDE.md`** in this template repo, the next agent you spawn
will automatically pick up the changes.

---

## Repo File Map

```
.openclaw/                      # Internal scripts + runtime state
  spawn-agent.sh                # Creates worktree + tmux session for an agent
  complete-task.sh              # Marks task done, notifies you via notifications.jsonl
  check-agents.sh               # Cron job: monitors agents every 10 min
  cleanup.sh                    # Cron job: cleans up finished tasks daily
  active-tasks.json             # Task registry (NEVER edit manually)
  notifications.jsonl           # Agent → JARVIS event queue (append-only)
  .notification-cursor          # Tracks last-read position in notifications.jsonl
  logs/<task_id>.log            # Per-agent logs
  prompts/<task_id>.md          # Stored prompts for each spawned task
  agent-question.txt            # Agent questions (check + clear after answering)

jarvis-tools/                   # YOUR tools (the ones you call directly)
  jarvis-create-task.sh         # TOOL 1 — spawn a coding task
  jarvis-poll-notifications.sh  # TOOL 2 — poll for completed tasks
  jarvis-redirect-agent.sh      # TOOL 3 — redirect a running agent
  jarvis-dashboard.sh           # Dashboard (optional)
  JARVIS-SYSTEM-PROMPT.md       # System prompt template

CLAUDE.md                       # Instructions loaded into every Claude Code agent
```

# Last updated: 2026-02-26