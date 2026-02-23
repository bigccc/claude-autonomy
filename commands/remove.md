---
description: "Remove a task from the autonomy task queue"
argument-hint: "<task-id> [--force]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/remove-task.sh:*)"]
---

# Remove Autonomy Task

Parse the user's input and execute the remove-task script. Properly quote all arguments:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/remove-task.sh" <task-id> [--force]
```

IMPORTANT: Do NOT use `$ARGUMENTS` directly. Extract the task ID and flags from the user's input.

Show the result. If removal was blocked due to dependencies or in-progress status, explain why and suggest using --force if appropriate.
