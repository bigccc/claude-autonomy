---
description: "Start autonomous development loop (executes tasks sequentially via Stop hook)"
argument-hint: "[--max-iterations N]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/start-loop.sh:*)", "Read(.autonomy/feature_list.json)", "Read(.autonomy/progress.txt)", "Read(.autonomy/config.json)"]
hide-from-slash-command-tool: "true"
---

# Start Autonomous Loop

Execute the loop activation script:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/start-loop.sh" $ARGUMENTS
```

Now begin working. Follow the Autonomy Protocol's 4-phase execution:

1. **Analyze**: Read `.autonomy/progress.txt`, `.autonomy/feature_list.json`, `.autonomy/config.json` — understand context, read related source files, identify affected areas
2. **Design**: Plan your approach, consider edge cases, write brief plan to progress.txt
3. **Implement**: Write code following the plan, commit with format: feat({id}): {title}
4. **Verify**: Run test_command/lint_command if configured, check all acceptance_criteria, set status to "done", append completion summary to progress.txt

When you finish the task, you MUST exit the conversation immediately. Do NOT wait, do NOT ask for confirmation, do NOT say "waiting for next task". Just exit. The Stop hook will automatically feed you the next task.

CRITICAL: Follow the verification requirements. Never mark a task done without passing all acceptance criteria.
