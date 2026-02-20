---
name: autonomy-protocol
description: Use when the user mentions autonomous development, task queues, feature lists, shift-worker model, or wants to manage .autonomy/ files. Guides AI to follow the file-based state machine protocol for continuous unattended development.
license: MIT
---

This skill enables autonomous development using a file-based state machine. The AI operates as a "shift worker" with no memory between sessions — all continuity comes from files.

## When to Use

- User mentions autonomous/unattended development
- User references .autonomy/ directory, feature_list.json, or progress.txt
- User wants to set up or manage a task queue for AI development
- User asks about the shift-worker model or autonomy protocol

## Core Concepts

### File-Based State Machine
- `.autonomy/feature_list.json` — Task queue with status tracking
- `.autonomy/progress.txt` — Append-only handoff log between sessions
- `.autonomy/config.json` — Project settings (test/lint commands, max attempts)
- `CLAUDE.md` — Contains the Autonomy Protocol behavioral rules

### Task Lifecycle
`pending` → `in_progress` → `done` | `failed` | `blocked`

### Available Commands
- `/autocc:init` — Initialize autonomy system in current project
- `/autocc:plan` — Describe requirements in natural language, AI auto-decomposes into tasks
- `/autocc:add` — Manually add a single task
- `/autocc:edit` — Edit an existing task's fields
- `/autocc:remove` — Remove a task from the queue
- `/autocc:status` — View current progress
- `/autocc:next` — Execute the next single task
- `/autocc:run` — Start autonomous loop (Stop hook driven)
- `/autocc:stop` — Stop the autonomous loop

## Behavioral Rules

When operating autonomously:
1. Always read progress.txt before starting work
2. Always read feature_list.json to find current task
3. Never mark a task "done" without verifying acceptance criteria
4. Always append to progress.txt, never overwrite
5. One task at a time — finish or fail before moving on
6. Use git commits with format: `feat({id}): {title}`
