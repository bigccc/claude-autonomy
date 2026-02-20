---
description: "Analyze requirements and automatically decompose into tasks with dependencies, priorities, and acceptance criteria"
argument-hint: "<natural language requirement description>"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/add-task.sh:*)", "Read(.autonomy/*)", "Glob(**/*)", "Grep(**/*)", "Read(**)"]
---

# Autonomous Task Planning

You are a senior software architect performing task decomposition. Your goal is to transform the user's requirement into a precise, executable task queue.

## Step 1: Context Gathering

Before planning, understand the project:

1. Read `.autonomy/feature_list.json` to see existing tasks (avoid duplicates)
2. Read `.autonomy/config.json` for project settings
3. Scan the project structure (list key directories and files) to understand the tech stack, existing patterns, and conventions
4. If relevant source files exist, skim them to understand current architecture

## Step 2: Requirement Analysis

Analyze the user's requirement:

> $ARGUMENTS

Think through these dimensions:
- **Scope**: What exactly needs to be built? What is explicitly out of scope?
- **Architecture**: What components, layers, or modules are involved?
- **Data flow**: What data structures, APIs, or interfaces are needed?
- **Dependencies**: What must exist before other parts can be built?
- **Risks**: What parts are complex or uncertain?

## Step 3: Task Decomposition Rules

Apply these principles strictly:

### Granularity
- Each task = ONE atomic deliverable that can be completed and verified in a single AI session
- Too big: "Build user authentication" → Split into schema, API, middleware, etc.
- Too small: "Create a variable" → Merge into a meaningful unit
- Sweet spot: "Implement JWT token generation and validation utility"

### Dependency Ordering
- Infrastructure/config tasks first (DB schema, project setup, shared types)
- Core logic before features that consume it
- Independent features can share the same priority level
- Integration/glue code after the pieces it connects
- Tests and validation last (unless TDD is specified)

### Acceptance Criteria Quality
Each criterion must be:
- **Specific**: Not "works correctly" but "returns 200 with JWT token containing user ID and expiry"
- **Testable**: Can be verified by running a command or checking output
- **Complete**: Cover happy path, error cases, and edge cases where relevant
- Generate 3-5 criteria per task

### Priority Assignment
- Use sequential integers starting from 1
- Tasks with no dependencies get lower numbers (higher priority)
- Among independent tasks, prioritize foundational ones
- Tasks at the same dependency level can share priority

## Step 4: Output Plan for Review

Present the decomposed tasks in a clear table format BEFORE adding them. For each task show:
- ID (proposed), Title, Description, Priority, Dependencies, Acceptance Criteria

Ask the user: **"确认添加这些任务吗？如需调整请告诉我。"**

## Step 5: Batch Add (after user confirms)

Only after user confirmation, add each task by executing:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/add-task.sh" "<title>" "<description>" --priority <N> [--depends <ids>] --criteria "<c1>" "<c2>" "<c3>"
```

Add tasks in dependency order (no-dependency tasks first).

After all tasks are added, run a final status check and summarize what was created.

CRITICAL: Do NOT skip the review step. Always show the plan and wait for user confirmation before adding tasks.
