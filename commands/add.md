---
description: "Add a new task to the autonomy task queue"
argument-hint: "\"title\" \"description\" [--priority N] [--parent PARENT_ID] [--depends F001,F002] [--criteria \"c1\" \"c2\"]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/add-task.sh:*)"]
---

# Add Autonomy Task

Parse the user's input and execute the add-task script. You MUST properly quote all arguments to prevent shell interpretation of special characters (parentheses, exclamation marks, etc.):

```
"${CLAUDE_PLUGIN_ROOT}/scripts/add-task.sh" "<title>" "<description>" [--priority N] [--parent PARENT_ID] [--depends IDs] [--criteria "<c1>" "<c2>"]
```

IMPORTANT: Do NOT use `$ARGUMENTS` directly. Instead, extract the title, description, and options from the user's input, then construct the command with each argument properly double-quoted. For example:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/add-task.sh" "修复 user 模块测试 (84个失败)" "分析失败原因并修复" --priority 1
```

After adding, confirm the task was added and show its ID. If the user didn't provide acceptance criteria, suggest they add some for better autonomous execution quality.
