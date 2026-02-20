---
description: "Initialize autonomous development system in current project"
argument-hint: "[project-name]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/init-autonomy.sh:*)"]
---

# Initialize Autonomy System

Execute the init script to set up the autonomous development structure:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/init-autonomy.sh" $ARGUMENTS
```

After initialization, explain the created structure to the user:
1. `.autonomy/feature_list.json` — the task queue, add features here
2. `.autonomy/progress.txt` — the handoff log between AI sessions
3. `.autonomy/config.json` — project-level settings (test_command, lint_command, etc.)
4. `CLAUDE.md` has been updated with the Autonomy Protocol

Suggest the user run `/autocc:add` to add their first task.
