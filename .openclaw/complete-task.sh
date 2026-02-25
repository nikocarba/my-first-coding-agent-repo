#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# .openclaw/complete-task.sh
# Called automatically by the agent's launch script when done.
# Updates the task registry and appends to the notification queue.
# JARVIS reads the notification queue via jarvis-poll-notifications.sh
# ══════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
REGISTRY="$REPO_ROOT/.openclaw/active-tasks.json"
NOTIFY_FILE="$REPO_ROOT/.openclaw/notifications.jsonl"

# ── Parse arguments ───────────────────────────────────────────
TASK_ID="" EXIT_CODE=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --id)         TASK_ID="$2";    shift 2 ;;
    --exit-code)  EXIT_CODE="$2";  shift 2 ;;
    *) echo "ERROR: Unknown argument: $1"; exit 1 ;;
  esac
done
[[ -z "$TASK_ID" ]] && { echo "ERROR: --id is required"; exit 1; }

COMPLETED_AT=$(date +%s%3N)

# ── Pull task info from registry ──────────────────────────────
TASK=$(jq --arg id "$TASK_ID" '.[] | select(.id == $id)' "$REGISTRY")
if [[ -z "$TASK" ]]; then
  echo "ERROR: Task '$TASK_ID' not found in registry."
  exit 1
fi
BRANCH=$(echo "$TASK" | jq -r '.branch')

# ── Check for PR on this branch ───────────────────────────────
PR_NUMBER=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number // empty' 2>/dev/null || true)
PR_NUMBER="${PR_NUMBER:-null}"

if [[ "$PR_NUMBER" != "null" && -n "$PR_NUMBER" ]]; then
  PR_CREATED="true"
else
  PR_CREATED="false"
fi

# ── Check CI and reviewer statuses (only if PR exists) ────────
CI_PASSED="false"
CLAUDE_REVIEW="false"
GEMINI_REVIEW="false"

if [[ "$PR_CREATED" == "true" ]]; then
  # CI: all checks must be SUCCESS
  CI_RESULT=$(gh pr checks "$PR_NUMBER" --json name,state 2>/dev/null || echo "[]")
  TOTAL_CHECKS=$(echo "$CI_RESULT" | jq 'length')
  if [[ "$TOTAL_CHECKS" -gt 0 ]]; then
    PASSED_CHECKS=$(echo "$CI_RESULT" | jq '[.[] | select(.state == "SUCCESS")] | length')
    [[ "$PASSED_CHECKS" == "$TOTAL_CHECKS" ]] && CI_PASSED="true"
  fi

  # Reviewer approvals from bots
  REVIEWS=$(gh pr reviews "$PR_NUMBER" --json author,state 2>/dev/null || echo "[]")

  # Use string comparison — avoids jq boolean-coercion edge cases
  CLAUDE_CHECK=$(echo "$REVIEWS" | jq -r \
    '[.[] | select(.author.login == "claude[bot]" and .state == "APPROVED")] | length')
  [[ "$CLAUDE_CHECK" -gt 0 ]] && CLAUDE_REVIEW="true"

  GEMINI_CHECK=$(echo "$REVIEWS" | jq -r \
    '[.[] | select(.author.login == "gemini-code-assist[bot]" and .state == "APPROVED")] | length')
  [[ "$GEMINI_CHECK" -gt 0 ]] && GEMINI_REVIEW="true"
fi

# ── Determine final status ─────────────────────────────────────
if [[ "$EXIT_CODE" -ne 0 ]]; then
  STATUS="failed"
  NOTE="Agent exited with code $EXIT_CODE. Check the log for details."
elif [[ "$PR_CREATED" == "false" ]]; then
  STATUS="failed"
  NOTE="No PR was created. Agent may have stalled or errored out."
elif [[ "$CI_PASSED" == "true" && "$CLAUDE_REVIEW" == "true" && "$GEMINI_REVIEW" == "true" ]]; then
  STATUS="done"
  NOTE="All checks passed. Ready to merge."
else
  STATUS="needs_review"
  NOTE="PR open but some checks are pending or failed. CI=$CI_PASSED, Claude=$CLAUDE_REVIEW, Gemini=$GEMINI_REVIEW"
fi

# ── Atomically update registry ────────────────────────────────
TMPFILE=$(mktemp)
jq \
  --arg  id          "$TASK_ID" \
  --arg  status      "$STATUS" \
  --arg  note        "$NOTE" \
  --arg  pr          "$PR_NUMBER" \
  --argjson completed "$COMPLETED_AT" \
  --argjson pr_created "$([ "$PR_CREATED" = "true" ] && echo true || echo false)" \
  --argjson ci_passed  "$([ "$CI_PASSED"  = "true" ] && echo true || echo false)" \
  --argjson claude_rev "$([ "$CLAUDE_REVIEW" = "true" ] && echo true || echo false)" \
  --argjson gemini_rev "$([ "$GEMINI_REVIEW" = "true" ] && echo true || echo false)" \
  'map(if .id == $id then . + {
     status:      $status,
     note:        $note,
     pr:          ($pr | if . == "null" then null else (. | tonumber) end),
     completedAt: $completed,
     checks: {
       prCreated:          $pr_created,
       ciPassed:           $ci_passed,
       claudeReviewPassed: $claude_rev,
       geminiReviewPassed: $gemini_rev
     }
   } else . end)' \
  "$REGISTRY" > "$TMPFILE" && mv "$TMPFILE" "$REGISTRY"

echo "📝 Task $TASK_ID → status: $STATUS"

# ── Append to JARVIS notification queue ───────────────────────
# This is the ONLY signal JARVIS needs to poll.
PR_VAL=$([ "$PR_NUMBER" = "null" ] && echo "null" || echo "$PR_NUMBER")
jq -n \
  --arg  task_id  "$TASK_ID" \
  --arg  status   "$STATUS" \
  --arg  note     "$NOTE" \
  --arg  pr       "$PR_VAL" \
  --argjson ts    "$COMPLETED_AT" \
  '{
    task_id:   $task_id,
    status:    $status,
    note:      $note,
    pr:        ($pr | if . == "null" then null else (. | tonumber) end),
    timestamp: $ts
  }' >> "$NOTIFY_FILE"

echo "🔔 JARVIS notified via notifications.jsonl"
echo "   Status: $STATUS"
echo "   Note:   $NOTE"
