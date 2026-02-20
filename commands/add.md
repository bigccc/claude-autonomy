---
description: "Add a new task to the autonomy task queue"
argument-hint: "\"title\" \"description\" [--priority N] [--depends F001,F002] [--criteria \"c1\" \"c2\"]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/add-task.sh:*)"]
---

# Add Autonomy Task

Execute the add-task script:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/add-task.sh" $ARGUMENTS
```

After adding, confirm the task was added and show its ID. If the user didn't provide acceptance criteria, suggest they add some for better autonomous execution quality.
