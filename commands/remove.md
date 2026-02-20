---
description: "Remove a task from the autonomy task queue"
argument-hint: "<task-id> [--force]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/remove-task.sh:*)"]
---

# Remove Autonomy Task

Execute the remove-task script:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/remove-task.sh" $ARGUMENTS
```

Show the result. If removal was blocked due to dependencies or in-progress status, explain why and suggest using --force if appropriate.
