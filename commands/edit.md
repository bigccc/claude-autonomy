---
description: "Edit an existing task in the autonomy task queue"
argument-hint: "<task-id> [--title \"...\"] [--desc \"...\"] [--priority N] [--status STATUS]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/edit-task.sh:*)"]
---

# Edit Autonomy Task

Parse the user's input and execute the edit-task script. You MUST properly quote all string arguments to prevent shell interpretation of special characters:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/edit-task.sh" <task-id> [--title "..."] [--desc "..."] [--priority N] [--status STATUS]
```

IMPORTANT: Do NOT use `$ARGUMENTS` directly. Instead, extract the task ID and options from the user's input, then construct the command with string values properly double-quoted.

Show the updated task details. If no fields were specified, suggest available options (--title, --desc, --priority, --status).
