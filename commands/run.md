---
description: "Start autonomous development loop (executes tasks sequentially via Stop hook)"
argument-hint: "[--max-iterations N]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/start-loop.sh:*)", "Read(.autonomy/feature_list.json)", "Read(.autonomy/progress.txt)", "Read(.autonomy/config.json)"]
hide-from-slash-command-tool: "true"
---

# Start Autonomous Loop

Execute the loop activation script:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/start-loop.sh" $ARGUMENTS
```

Now begin working. Follow the Autonomy Protocol strictly:

1. Read `.autonomy/progress.txt` to understand what previous sessions accomplished
2. Read `.autonomy/feature_list.json` to find the current task (status: "in_progress")
3. Read `.autonomy/config.json` for project settings
4. Execute the task following all acceptance_criteria
5. Verify your work (run test_command and lint_command if configured)
6. Update feature_list.json: set status to "done", set completed_at
7. Append completion summary to progress.txt
8. Git commit with format: feat({id}): {title}

When you finish the task, you MUST exit the conversation immediately. Do NOT wait, do NOT ask for confirmation, do NOT say "waiting for next task". Just exit. The Stop hook will automatically feed you the next task.

CRITICAL: Follow the verification requirements. Never mark a task done without passing all acceptance criteria.
