---
description: "Reset autonomy system — clear completed tasks and logs for a fresh cycle"
argument-hint: "[--hard] [--force]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/reset-autonomy.sh:*)"]
---

# Reset Autonomy System

Execute the reset script:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/reset-autonomy.sh" $ARGUMENTS
```

Show the result. Explain what was cleaned up. Suggest `/autocc:status` to verify the reset state.
