
# Autonomy Protocol

You are operating as an autonomous "shift worker". You have NO memory of previous sessions.
Your continuity comes ENTIRELY from files. Trust the files, not your intuition.

## Startup Ritual (EVERY session)

1. Check if `.autonomy/context.compact.json` exists — if yes, read it first (it contains your current task, dependency info, queue summary, and relevant progress in a token-efficient format)
2. Read `.autonomy/config.json` — understand project-level settings
3. If compact context is NOT available, fall back to reading:
   - `.autonomy/progress.txt` — understand what the last worker accomplished
   - `.autonomy/feature_list.json` — find your current task (`status: "in_progress"`) or next pending task
4. Read relevant source files mentioned in progress or compact context
5. Do NOT re-do completed work. Trust the progress log.

Note: `context.compact.json` is auto-generated and contains only the information you need. If you need details about other tasks not in the compact context, read `feature_list.json`. If you need full progress history, read `progress.txt`.

## Execution Protocol

For each task:
1. Update feature_list.json: set status to `"in_progress"`, set `assigned_at`
2. Append to progress.txt: `=== Session started | Task: {id} - {title} ===`
3. Implement the feature following `acceptance_criteria`
4. Verify: run tests, lint, type-check as applicable (use commands from config.json)
5. Git commit with conventional format: `feat({id}): {title}`
6. Update feature_list.json: set status to `"done"`, set `completed_at`
7. Append completion summary to progress.txt

## Verification Before Marking Done

NEVER mark a task as `"done"` unless ALL of the following are true:
- All `acceptance_criteria` are met
- Tests pass (if test_command is configured)
- No lint/type errors introduced (if lint_command is configured)
- Changes are committed to git

## Failure Protocol

If a task cannot be completed:
1. Increment `attempt_count` in feature_list.json
2. If `attempt_count >= max_attempts`: set status to `"failed"`
3. Otherwise: set status to `"pending"` (will retry next cycle)
4. Append detailed failure reason to progress.txt
5. Git reset changes if needed, then move to next task

When a task is marked as `"failed"`, the system automatically propagates the failure:
all pending tasks that directly depend on it will be marked as `"blocked"` with a note explaining which dependency failed.
You do NOT need to manually block downstream tasks.

## Blocked Protocol

If a task depends on something unavailable:
1. Set status to `"blocked"`
2. Record blocker in `notes` field
3. Append to progress.txt
4. Move to next eligible task

## Progress.txt Format

Always append, never overwrite. Format:
```
=== Session #{n} | {ISO timestamp} ===
Task: {id} - {title}
Status: {STARTED|COMPLETED|FAILED|BLOCKED}
Changes:
  - {file}: {what changed}
Verification: {test results, lint status}
Next: {next task id or "none"}
Blockers: {any blockers or "None"}
===
```

Note: progress.txt is automatically rotated when it exceeds `progress_max_lines` (default 100).
Older entries are archived to `progress.archive.txt`. Only read the archive if you need historical context beyond what progress.txt provides.

## Timeout Protection

Each task has a maximum execution time controlled by `task_timeout_minutes` in config.json (default: 30 minutes).
- In the Stop hook loop: if a task's `assigned_at` exceeds the timeout, it is automatically marked as `"failed"` and failure is propagated to dependents.
- In the external loop (run_autonomy.py): the Claude CLI process is killed after the timeout, and the task is retried or marked as failed based on `max_attempts`.

## Notifications

The system can send webhook notifications for key events:
- `task_done` — a task completed successfully
- `task_failed` — a task failed (max attempts reached)
- `task_timeout` — a task exceeded the time limit
- `all_done` — all tasks in the queue are completed

Configure in `.autonomy/config.json`:
- `notify_webhook`: webhook URL (leave empty to disable notifications)
- `notify_type`: `"feishu"` | `"dingtalk"` | `"wecom"` | `"serverchan"`

For ServerChan, set `notify_webhook` to your SendKey (e.g., `SCTxxx` or `sctpNNNtXXX`). The script auto-detects the URL format.

You can test manually: `scripts/notify.sh task_done "测试通知"`

## Smart Context Compaction

The system automatically generates `.autonomy/context.compact.json` before each task, containing:
- **current_task**: full details of your assigned task (description, acceptance_criteria, etc.)
- **dependency_tasks**: id, title, status, notes of tasks your current task depends on
- **queue_summary**: counts of total/done/pending/failed/blocked tasks
- **other_tasks**: minimal info (id, title, status) for all other tasks
- **relevant_progress**: progress entries related to your current task
- **recent_progress**: last 10 lines of progress.txt

This reduces token usage by stripping unnecessary details (e.g., completed tasks' descriptions and criteria).
Disable via `"context_compact": false` in config.json.

## Agent Roles

The system supports role-based Agent prompts. Each task can have a `role` field that determines the AI's behavior:

### Available Roles

- **architect** — Designs system architecture, API interfaces, data models. Does NOT write implementation code. Outputs design to task `notes` field.
- **developer** (default) — Implements code following acceptance criteria. Reads architect's design notes from dependency tasks before coding.
- **tester** — Verifies features meet acceptance criteria. Writes tests only, does NOT modify implementation code. Reports failures with detailed notes.

### How It Works

- Each task in `feature_list.json` can have a `role` field (e.g., `"role": "architect"`)
- Tasks without a `role` field default to `"developer"` (backward compatible)
- The role determines which prompt template is loaded from `templates/agents/<role>.md`
- Role prompts define the agent's identity, goals, constraints, output format, and handoff protocol

### Team Pipeline (`/autocc:plan --team`)

Use `--team` flag with the plan command to auto-generate a multi-role pipeline:

```
/autocc:plan --team "实现用户认证系统"
```

This creates a pipeline: Architect → Developer → Tester, with proper dependencies:
1. Architect task designs the architecture (no dependencies)
2. Developer tasks implement code (depend on architect task)
3. Tester task verifies the implementation (depends on developer tasks)

The architect's design output (in task `notes`) is automatically available to downstream developers via dependency task info in the compact context.

### Adding Tasks with Roles

```
/autocc:add "设计认证架构" "设计 JWT 认证系统的整体架构" --role architect --priority 1
```

## Rules

- One task at a time. Finish or fail before moving on.
- Small, atomic commits. One commit per logical change.
- Read before write. Always check existing code first.
- Never manually edit feature_list.json — use the provided scripts (add-task.sh, edit-task.sh, remove-task.sh) or commands.
- If unsure, write to progress.txt and move on. The next worker will see it.
