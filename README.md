# my-first-coding-agent-repo

A starter repository for **OpenClaw** — a system that lets you spawn and manage coding agents at zero communication cost.

## What is this?

This repo contains the scripts and configuration needed to run **JARVIS**: a two-tier AI agent system where:

- **JARVIS** = orchestrator. He has business context, memory, and customer info. He spawns tasks and supervises agents.
- **Code agents** = coders. They implement, test, and open PRs. They only know what you tell them.

## What can I do with it?

- Spawn coding agents to build features, fix bugs, or refactor code
- Agents work autonomously in tmux sessions
- Communication is file-based (zero API cost between you and agents)
- Agents create branches, commit code, and open PRs automatically

## Quick Start

### Prerequisites

```bash
git --version    # >= 2.20
tmux -V          # installed
jq --version     # >= 1.6
gh --version     # GitHub CLI, authenticated
claude --version # Claude Code CLI installed
```

### Run the setup

```bash
bash setup.sh
```

This will verify dependencies, configure paths, and print the cron commands you need.

### Spawn your first agent

```bash
echo '{
  "id": "hello-world",
  "branch": "feat/hello-world",
  "description": "Say hello",
  "prompt": "Create a file called HELLO.md that says Hello from Claude Code!"
}' | jarvis-tools/jarvis-create-task.sh
```

### Monitor the agent

```bash
tmux attach -t claude-hello-world
```

### Check for results

```bash
jarvis-tools/jarvis-poll-notifications.sh
```

## Available Scripts

| Script | Purpose |
|--------|---------|
| `jarvis-tools/jarvis-create-task.sh` | Spawn a new coding agent |
| `jarvis-tools/jarvis-poll-notifications.sh` | Check for completed tasks |
| `jarvis-tools/jarvis-redirect-agent.sh` | Redirect a stuck agent |
| `jarvis-tools/jarvis-dashboard.sh` | Live terminal dashboard for all tasks |
| `.openclaw/check-agents.sh` | Cron job to monitor agents (run every 10 min) |
| `.openclaw/cleanup.sh` | Cron job to clean up old sessions (run daily) |

## File Structure

```
.
├── .openclaw/                              # OpenClaw internal scripts + runtime
│   ├── spawn-agent.sh                      # Spawns a Claude Code agent in a worktree
│   ├── complete-task.sh                    # Marks a task done and notifies JARVIS
│   ├── check-agents.sh                    # Cron: monitors running agents every 10 min
│   ├── cleanup.sh                          # Cron: cleans up finished tasks daily
│   ├── active-tasks.json                   # (runtime — gitignored)
│   ├── notifications.jsonl                 # (runtime — gitignored)
│   └── logs/                               # (runtime — gitignored)
├── jarvis-tools/                           # JARVIS orchestrator tools
│   ├── jarvis-create-task.sh               # Spawn a new coding agent
│   ├── jarvis-poll-notifications.sh        # Check for completed tasks
│   ├── jarvis-redirect-agent.sh            # Redirect a stuck agent
│   ├── jarvis-dashboard.sh                 # Live terminal dashboard
│   └── JARVIS-SYSTEM-PROMPT.md             # System prompt template for JARVIS
├── CLAUDE.md                               # Instructions for Claude Code agents
├── JARVIS-MISSION.md                       # Full setup guide for JARVIS
├── SOUL.md                                 # JARVIS identity and personality
├── setup.sh                                # Initial setup script
└── README.md                               # This file
```

## Learn More

- Full setup guide: See [JARVIS-MISSION.md](./JARVIS-MISSION.md)
- System prompt: See [jarvis-tools/JARVIS-SYSTEM-PROMPT.md](./jarvis-tools/JARVIS-SYSTEM-PROMPT.md)
- OpenClaw docs: https://docs.openclaw.ai

## Requirements

- GitHub account with CLI (`gh`) authenticated
- Claude Code subscription
- tmux
- jq
- Git >= 2.20
