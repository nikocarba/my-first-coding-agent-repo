#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# jarvis-dashboard.sh
# Live terminal dashboard for all JARVIS agent tasks.
#
# Usage:
#   bash jarvis-dashboard.sh               # one-shot snapshot
#   bash jarvis-dashboard.sh --watch       # refresh every 5s
#   bash jarvis-dashboard.sh --watch 10    # refresh every 10s
#   bash jarvis-dashboard.sh --task <id>   # drill into one task's log
#   bash jarvis-dashboard.sh --json        # dump registry as pretty JSON
# ══════════════════════════════════════════════════════════════

set -euo pipefail

# ── Resolve paths ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
REGISTRY="$REPO_ROOT/.openclaw/active-tasks.json"
NOTIFY_FILE="$REPO_ROOT/.openclaw/notifications.jsonl"
CURSOR_FILE="$REPO_ROOT/.openclaw/.notification-cursor"
LOG_DIR="$REPO_ROOT/.openclaw/logs"

# ── ANSI colours ──────────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"
WHITE="\033[37m"
BG_BLUE="\033[44m"
BG_RED="\033[41m"
BG_GREEN="\033[42m"
BG_YELLOW="\033[43m"

# ── Parse arguments ───────────────────────────────────────────
MODE="snapshot"        # snapshot | watch | task | json
WATCH_INTERVAL=5
TASK_FILTER=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --watch)
      MODE="watch"
      if [[ $# -gt 1 && "$2" =~ ^[0-9]+$ ]]; then
        WATCH_INTERVAL="$2"; shift
      fi
      shift ;;
    --task)
      MODE="task"
      TASK_FILTER="$2"; shift 2 ;;
    --json)
      MODE="json"; shift ;;
    -h|--help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "Unknown argument: $1. Use --help for usage."; exit 1 ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────

# Pad or truncate a string to exactly N chars
padtrunc() {
  local str="$1" width="$2"
  printf "%-${width}.${width}s" "$str"
}

# Human-readable elapsed time from a unix-ms timestamp
elapsed() {
  local ts_ms="$1"
  local now_ms now_s ts_s diff
  now_ms=$(date +%s%3N)
  now_s=$(( now_ms / 1000 ))
  ts_s=$(( ts_ms / 1000 ))
  diff=$(( now_s - ts_s ))
  if   [[ $diff -lt 60    ]]; then echo "${diff}s ago"
  elif [[ $diff -lt 3600  ]]; then echo "$(( diff / 60 ))m ago"
  elif [[ $diff -lt 86400 ]]; then echo "$(( diff / 3600 ))h ago"
  else                              echo "$(( diff / 86400 ))d ago"
  fi
}

# Colour for a task status string
status_color() {
  case "$1" in
    running)      echo -e "${BOLD}${CYAN}$1${RESET}" ;;
    done)         echo -e "${BOLD}${GREEN}$1${RESET}" ;;
    needs_review) echo -e "${BOLD}${YELLOW}$1${RESET}" ;;
    failed)       echo -e "${BOLD}${RED}$1${RESET}" ;;
    *)            echo -e "${DIM}$1${RESET}" ;;
  esac
}

# Tick/cross for a boolean
check_mark() {
  [[ "$1" == "true" ]] && echo -e "${GREEN}✔${RESET}" || echo -e "${DIM}✘${RESET}"
}

# ── MODE: json ────────────────────────────────────────────────
if [[ "$MODE" == "json" ]]; then
  jq '.' "$REGISTRY"
  exit 0
fi

# ── MODE: task (log drill-down) ───────────────────────────────
if [[ "$MODE" == "task" ]]; then
  if [[ -z "$TASK_FILTER" ]]; then
    echo "ERROR: --task requires a task ID"; exit 1
  fi

  LOG_FILE="$LOG_DIR/$TASK_FILTER.log"
  if [[ ! -f "$LOG_FILE" ]]; then
    echo "No log found for task: $TASK_FILTER"
    echo "Expected: $LOG_FILE"
    exit 1
  fi

  TASK=$(jq -r --arg id "$TASK_FILTER" '.[] | select(.id == $id)' "$REGISTRY" 2>/dev/null || true)
  if [[ -z "$TASK" ]]; then
    echo "Task '$TASK_FILTER' not found in registry."
    exit 1
  fi

  STATUS=$(echo "$TASK" | jq -r '.status')
  BRANCH=$(echo "$TASK" | jq -r '.branch')
  STARTED=$(echo "$TASK" | jq -r '.startedAt')
  NOTE=$(echo "$TASK" | jq -r '.note // ""')

  echo -e "${BOLD}${BG_BLUE}  Task: $TASK_FILTER  ${RESET}"
  echo -e "  Branch:  ${CYAN}$BRANCH${RESET}"
  echo -e "  Status:  $(status_color "$STATUS")"
  echo -e "  Started: $(elapsed "$STARTED")"
  [[ -n "$NOTE" ]] && echo -e "  Note:    ${YELLOW}$NOTE${RESET}"
  echo ""
  echo -e "${BOLD}── Last 50 lines of log ─────────────────────────────────${RESET}"
  tail -n 50 "$LOG_FILE"
  exit 0
fi

# ── RENDER function (used by both snapshot and watch) ─────────
render() {
  # ── Guard: registry must exist ──────────────────────────────
  if [[ ! -f "$REGISTRY" ]]; then
    echo -e "${RED}Registry not found: $REGISTRY${RESET}"
    echo "Run setup.sh first."
    return
  fi

  # ── Header ──────────────────────────────────────────────────
  local now
  now=$(date '+%Y-%m-%d %H:%M:%S')
  local repo_name
  repo_name=$(basename "$REPO_ROOT")

  echo -e "${BOLD}${BG_BLUE}                                                          ${RESET}"
  echo -e "${BOLD}${BG_BLUE}  JARVIS Dashboard — ${repo_name}   ${DIM}${now}  ${RESET}"
  echo -e "${BOLD}${BG_BLUE}                                                          ${RESET}"
  echo ""

  # ── Summary counts ──────────────────────────────────────────
  local total running done failed review
  total=$(   jq 'length'                                            "$REGISTRY")
  running=$(  jq '[.[] | select(.status=="running")]      | length' "$REGISTRY")
  done=$(     jq '[.[] | select(.status=="done")]         | length' "$REGISTRY")
  failed=$(   jq '[.[] | select(.status=="failed")]       | length' "$REGISTRY")
  review=$(   jq '[.[] | select(.status=="needs_review")] | length' "$REGISTRY")

  echo -e "  Tasks: ${BOLD}$total${RESET}  |  "\
"${CYAN}▶ $running running${RESET}  "\
"${GREEN}✔ $done done${RESET}  "\
"${YELLOW}⚑ $review needs_review${RESET}  "\
"${RED}✖ $failed failed${RESET}"
  echo ""

  # ── Task table header ────────────────────────────────────────
  echo -e "${BOLD}$(padtrunc "ID" 28)  $(padtrunc "STATUS" 12)  $(padtrunc "BRANCH" 30)  $(padtrunc "AGO" 8)  PR   CI  CL  GE${RESET}"
  echo -e "${DIM}$(printf '%.0s─' {1..95})${RESET}"

  # ── Task rows ────────────────────────────────────────────────
  local task_count
  task_count=$(jq 'length' "$REGISTRY")

  if [[ "$task_count" -eq 0 ]]; then
    echo -e "  ${DIM}No tasks yet. Use jarvis-create-task.sh to spawn an agent.${RESET}"
  else
    while IFS= read -r task; do
      local id status branch started pr pr_created ci claude gemini note tmux_alive
      id=$(         echo "$task" | jq -r '.id')
      status=$(     echo "$task" | jq -r '.status')
      branch=$(     echo "$task" | jq -r '.branch')
      started=$(    echo "$task" | jq -r '.startedAt')
      pr=$(         echo "$task" | jq -r '.pr // "—"')
      pr_created=$( echo "$task" | jq -r '.checks.prCreated')
      ci=$(         echo "$task" | jq -r '.checks.ciPassed')
      claude=$(     echo "$task" | jq -r '.checks.claudeReviewPassed')
      gemini=$(     echo "$task" | jq -r '.checks.geminiReviewPassed')
      note=$(       echo "$task" | jq -r '.note // ""')

      # Check if tmux session is alive (only matters for running tasks)
      local tmux_session
      tmux_session=$(echo "$task" | jq -r '.tmuxSession')
      tmux_alive=""
      if [[ "$status" == "running" ]]; then
        if tmux has-session -t "$tmux_session" 2>/dev/null; then
          tmux_alive=" ${GREEN}[tmux ✔]${RESET}"
        else
          tmux_alive=" ${RED}[tmux ✘]${RESET}"
        fi
      fi

      local age
      age=$(elapsed "$started")

      # Format PR column
      local pr_col
      if [[ "$pr" == "null" || "$pr" == "—" ]]; then
        pr_col="${DIM}—${RESET}  "
      else
        pr_col="${CYAN}#${pr}${RESET}"
      fi

      printf "%-28s  " "$id"
      echo -ne "$(status_color "$status")$(padtrunc "" $((12 - ${#status})))  "
      printf "%-30s  %-8s  " "$branch" "$age"
      echo -ne "$pr_col  $(check_mark "$ci")   $(check_mark "$claude")   $(check_mark "$gemini")"
      echo -e "$tmux_alive"

      # Print note if present (indented)
      if [[ -n "$note" ]]; then
        echo -e "   ${DIM}↳ $note${RESET}"
      fi

    done < <(jq -c '.[]' "$REGISTRY")
  fi

  echo ""

  # ── Active tmux sessions ─────────────────────────────────────
  echo -e "${BOLD}── tmux sessions ────────────────────────────────────────${RESET}"
  local sessions
  sessions=$(tmux list-sessions -F '#S' 2>/dev/null | grep '^claude-' || true)
  if [[ -z "$sessions" ]]; then
    echo -e "  ${DIM}No active claude-* sessions.${RESET}"
  else
    while IFS= read -r s; do
      echo -e "  ${CYAN}$s${RESET}  — attach: tmux attach -t $s"
    done <<< "$sessions"
  fi
  echo ""

  # ── Recent notifications ─────────────────────────────────────
  echo -e "${BOLD}── Recent notifications (last 5) ────────────────────────${RESET}"
  if [[ ! -f "$NOTIFY_FILE" ]] || [[ ! -s "$NOTIFY_FILE" ]]; then
    echo -e "  ${DIM}No notifications yet.${RESET}"
  else
    tail -n 5 "$NOTIFY_FILE" | while IFS= read -r line; do
      local n_id n_status n_note n_ts
      n_id=$(    echo "$line" | jq -r '.task_id')
      n_status=$(echo "$line" | jq -r '.status')
      n_ts=$(    echo "$line" | jq -r '.timestamp')
      n_note=$(  echo "$line" | jq -r '.note // ""')
      local n_age
      n_age=$(elapsed "$n_ts")
      echo -ne "  ${DIM}$n_age${RESET}  $(padtrunc "$n_id" 28)  $(status_color "$n_status")"
      [[ -n "$n_note" ]] && echo -e "  ${DIM}$n_note${RESET}" || echo ""
    done
  fi
  echo ""

  # ── Log tails for running tasks ──────────────────────────────
  local running_ids
  mapfile -t running_ids < <(jq -r '.[] | select(.status=="running") | .id' "$REGISTRY")

  if [[ ${#running_ids[@]} -gt 0 ]]; then
    echo -e "${BOLD}── Live log tails (running tasks) ───────────────────────${RESET}"
    for rid in "${running_ids[@]}"; do
      local log_path="$LOG_DIR/$rid.log"
      echo -e "  ${CYAN}$rid${RESET}"
      if [[ -f "$log_path" ]]; then
        tail -n 6 "$log_path" | sed 's/^/    /'
      else
        echo -e "    ${DIM}(no log yet)${RESET}"
      fi
      echo ""
    done
  fi

  # ── Footer ───────────────────────────────────────────────────
  if [[ "$MODE" == "watch" ]]; then
    echo -e "${DIM}  Refreshing every ${WATCH_INTERVAL}s — Ctrl+C to exit${RESET}"
  else
    echo -e "${DIM}  Tip: run with --watch for live updates, --task <id> to tail a log${RESET}"
  fi
}

# ── MODE: snapshot ────────────────────────────────────────────
if [[ "$MODE" == "snapshot" ]]; then
  render
  exit 0
fi

# ── MODE: watch ───────────────────────────────────────────────
while true; do
  clear
  render
  sleep "$WATCH_INTERVAL"
done
