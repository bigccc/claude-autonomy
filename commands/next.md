---
description: "Execute the next pending task (single task, no loop)"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/next-task.sh)", "Read(.autonomy/feature_list.json)", "Read(.autonomy/progress.txt)", "Read(.autonomy/config.json)"]
---

# Execute Next Task

Get the next eligible task:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/next-task.sh"
```

Now follow the Autonomy Protocol to execute this single task:

1. Read `.autonomy/progress.txt` — understand context from previous sessions
2. Read `.autonomy/feature_list.json` — get full details of the assigned task
3. Read `.autonomy/config.json` — get project settings
4. Implement the task, following all acceptance_criteria
5. Verify your work (run test_command and lint_command if configured)
6. Update feature_list.json: set status to "done", set completed_at
7. Append completion summary to progress.txt
8. Git commit with format: feat({id}): {title}

This is a single-task execution. After completing, report the result to the user.
