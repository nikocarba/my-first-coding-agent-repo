# AGENTS.md
# Instructions for Claude Code Agents
#
# This file is loaded into every Claude Code agent's context window.
# It contains ONLY coding conventions. Business context is in your task prompt.
# ══════════════════════════════════════════════════════════════

## Your Role

You are a focused coding agent. JARVIS (your orchestrator) has already done
all the business reasoning and distilled it into your task prompt.
Your job: implement the task, write tests, open a PR. Nothing else.

---

## Definition of Done

You are NOT done until ALL of the following are true:

- [ ] Code is committed and pushed to your branch
- [ ] `git rebase origin/main` — branch is conflict-free with main
- [ ] PR is open (`gh pr create --fill`)
- [ ] CI passes: lint, typecheck, unit tests, E2E
- [ ] If any UI was changed: a screenshot is in the PR description
- [ ] PR description explains WHAT changed and WHY

Do not stop until every box above is checked.

---

## Step-by-Step Workflow

```bash
# 1. Orient yourself
cat AGENTS.md                     # you are reading this
ls src/types/                     # understand the type system first
grep -r "TODO\|FIXME" src/ --include="*.ts" | head -20  # any relevant hints

# 2. Implement the task
# ... make your changes ...

# 3. Test before pushing
pnpm lint && pnpm typecheck && pnpm test
# If those commands don't exist, try: npm run lint && npm test

# 4. Commit and push
git add -A
git commit -m "feat: <short description of what you did>"
git rebase origin/main            # stay in sync
git push -u origin HEAD

# 5. Open the PR
gh pr create --fill --body "$(cat <<'PRBODY'
## What changed
<describe the change>

## Why
<from your task prompt — copy the customer/business reason>

## How to test
<steps to verify>

## Screenshots
<paste screenshot here if UI changed — CI will fail without it>
PRBODY
)"
```

---

## Repo Conventions

- **TypeScript strict mode** — zero `any` types allowed
- **Components** live in `src/components/`
- **Types** live in `src/types/`
- **Tests** are co-located: `Foo.test.ts` next to `Foo.ts`
- **Before creating anything new**, grep for existing patterns:
  ```bash
  grep -r "similar concept" src/ --include="*.ts" -l
  ```

---

## If You Are Stuck or Need Clarification

Write your question to this file — JARVIS monitors it:

```bash
echo "QUESTION: <your specific question here>" > .openclaw/agent-question.txt
```

JARVIS will read this during her monitoring loop and send you an answer
directly into this terminal session via tmux. Wait a few minutes.

---

## Hard Rules

- **Never push to `main` directly.** Always use your assigned branch.
- **Never modify package.json versions** unless explicitly instructed.
- **Never delete files** without documenting it clearly in the PR description.
- **Never call external APIs** not already present in the codebase.
- **Never leave `console.log` debug statements** in committed code.
