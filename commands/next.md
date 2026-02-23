---
description: "Execute the next pending task (single task, no loop)"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/next-task.sh)", "Read(.autonomy/feature_list.json)", "Read(.autonomy/progress.txt)", "Read(.autonomy/config.json)"]
---

# Execute Next Task

Get the next eligible task:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/next-task.sh"
```

Now follow the Autonomy Protocol's 4-phase execution:

1. **Analyze**: Read `.autonomy/progress.txt`, `.autonomy/feature_list.json`, `.autonomy/config.json` — understand context, read related source files, identify affected areas
2. **Design**: Plan your approach, consider edge cases, write brief plan to progress.txt
3. **Implement**: Write code following the plan, commit with format: feat({id}): {title}
4. **Verify**: Run test_command/lint_command if configured, check all acceptance_criteria, set status to "done", append completion summary to progress.txt

This is a single-task execution. After completing, report the result to the user.
