---
description: "Analyze requirements and automatically decompose into tasks with dependencies, priorities, and acceptance criteria"
argument-hint: "<natural language requirement description> [--team] [--deep] [--brainstorm]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/add-task.sh:*)", "Read(.autonomy/*)", "Glob(**/*)", "Grep(**/*)", "Read(**)"]
---

# Autonomous Task Planning

You are a senior software architect performing task decomposition. Your goal is to transform the user's requirement into a precise, executable task queue.

## Brainstorm Mode Detection

Check if the user's input contains `--brainstorm` flag. If present, activate **Brainstorm Mode** before proceeding to normal planning:

### Brainstorm Flow

1. **Acknowledge** the requirement and state you'll ask clarifying questions first
2. **Ask 3-5 targeted questions** covering these dimensions (pick the most relevant):
   - **Tech Stack**: What technologies, frameworks, or libraries should be used? Any constraints?
   - **Architecture**: Monolith vs microservices? Existing patterns to follow? Preferred design patterns?
   - **Priority**: What's the MVP? What can be deferred to later iterations?
   - **Scope**: What's explicitly in scope vs out of scope? Any hard boundaries?
   - **Constraints**: Performance requirements? Security concerns? Compatibility needs? Timeline?
3. **Wait for user answers** — do NOT proceed until the user responds
4. **Summarize** the brainstorm findings in a brief "Requirements Summary" block
5. **Continue** with the normal planning flow (Step 1: Context Gathering) using the clarified requirements

Note: Brainstorm mode can be combined with `--team` and `--deep` flags.

## Team Mode Detection

Check if the user's input contains `--team` flag. If present, activate **Team Pipeline Mode** (see below).

## Deep Mode Detection

Check if the user's input contains `--deep` flag. If present, activate **Deep Exploration Mode** (see Step 2.5 below) regardless of scale.

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

### Scale Detection & Deep Exploration (Step 2.5)

Before decomposing, assess the scale of the requirement:

**Auto-detection**: If the requirement involves batch operations on a collection (e.g., "all APIs", "all endpoints", "all modules", "all pages", "all interfaces", "覆盖所有", "全部接口"), or if `--deep` flag is present, you MUST:

1. **Explore first**: Scan and list ALL targets (API routes, endpoints, files, controllers, etc.)
   - Use Glob and Grep to find all relevant files and endpoints
   - Parse route definitions, controller files, or API specs
2. **Count and categorize**: Group targets by module/directory/type, report counts per group
3. **Present exploration summary** to the user before decomposing:
   - Total count of targets found
   - Breakdown by category/module (e.g., "outapi: 120 endpoints, adminapi: 85 endpoints, api: 300 endpoints")
   - Proposed batch size per task (default: 5-15 targets per task)
   - Estimated total number of tasks
4. **Wait for user confirmation** on the exploration summary before proceeding to decomposition

**Batch Decomposition Rules** (when target count > 15):
- Each task should handle **5-15 targets** (e.g., 5-15 API endpoints per task)
- Group by logical module/directory, but **split large modules into multiple tasks**
- Name tasks specifically with batch info: `"测试 outapi 接口 (1/6): user, auth, profile"` not `"测试 outapi 接口"`
- Include the **exact target list** in each task's description and acceptance_criteria
- **NEVER** create a single task covering more than 15 targets
- Use `--parent` with add-task.sh to create subtasks under a parent when decomposing a large logical group

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
- ID (proposed), Title, Role (if team mode), Description, Priority, Dependencies, Acceptance Criteria

Ask the user: **"确认添加这些任务吗？如需调整请告诉我。"**

## Step 5: Batch Add (after user confirms)

Only after user confirmation, add each task by executing:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/add-task.sh" "<title>" "<description>" --priority <N> [--role <role>] [--depends <ids>] --criteria "<c1>" "<c2>" "<c3>"
```

Add tasks in dependency order (no-dependency tasks first).

After all tasks are added, run a final status check and summarize what was created.

CRITICAL: Do NOT skip the review step. Always show the plan and wait for user confirmation before adding tasks.

---

## Team Pipeline Mode (--team)

When `--team` flag is detected, generate a multi-role pipeline with architect → developer → tester flow:

### Pipeline Structure

1. **Architect tasks** (lowest priority numbers = execute first)
   - Role: `architect`
   - Design system architecture, API interfaces, data models
   - Output: technical design written to task `notes` field
   - No implementation code

2. **Developer tasks** (medium priority numbers)
   - Role: `developer`
   - Implement code based on architect's design
   - Each developer task depends on its corresponding architect task
   - Follow acceptance criteria precisely

3. **Tester tasks** (highest priority numbers = execute last)
   - Role: `tester`
   - Verify implemented features meet acceptance criteria
   - Each tester task depends on the developer tasks it verifies
   - Write tests, do NOT modify implementation code

### Example Pipeline

For requirement "实现用户认证系统":

```
F001 [architect]  设计用户认证系统架构        (priority: 1, deps: none)
F002 [developer]  实现 JWT 工具函数           (priority: 2, deps: F001)
F003 [developer]  实现认证中间件              (priority: 3, deps: F001)
F004 [developer]  实现登录/注册 API           (priority: 4, deps: F002,F003)
F005 [tester]     验证用户认证系统            (priority: 5, deps: F002,F003,F004)
```

### Team Mode Rules

- Always start with ONE architect task that covers the overall design
- Developer tasks depend on the architect task and read its `notes` for design guidance
- Group related tester tasks — one tester task can verify multiple developer tasks
- Keep the pipeline lean: avoid creating too many fine-grained architect or tester tasks
- If the requirement is simple (single feature), the pipeline can be as short as 3 tasks (1 architect + 1 developer + 1 tester)
