---
description: "Edit an existing task in the autonomy task queue"
argument-hint: "<task-id> [--title \"...\"] [--desc \"...\"] [--priority N] [--status STATUS]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/edit-task.sh:*)"]
---

# Edit Autonomy Task

Execute the edit-task script:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/edit-task.sh" $ARGUMENTS
```

Show the updated task details. If no fields were specified, suggest available options (--title, --desc, --priority, --status).
