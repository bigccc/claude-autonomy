# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

claude-autonomy 是一个 Claude Code 插件，实现"轮班工人"模式的自主开发系统。核心机制：文件状态机 + Stop Hook 拦截，让 AI 无人值守地逐个完成任务队列。

系统要求：macOS + jq + Claude Code CLI。

## 架构

### 核心循环

```
/autocc:run → AI 执行任务 → 退出会话 → Stop Hook 拦截
  → 检查队列/超时/迭代次数 → 生成精简上下文 → 注入下一个任务提示 → AI 继续
```

### 文件状态机（运行时在项目的 .autonomy/ 目录）

- `feature_list.json` — 任务队列（状态流转：pending → in_progress → done/failed/blocked）
- `progress.txt` — 会话交接日志（append-only，超限自动轮转到 progress.archive.txt）
- `config.json` — 项目配置（test_command, lint_command, task_timeout_minutes, 通知等）
- `context.compact.json` — 自动生成的精简上下文，减少 token 消耗

### 关键组件

- `hooks/stop-hook.sh` — 核心 Hook，拦截 AI 退出并注入下一个任务。检查迭代次数、超时、未提交变更，调用 compact-context、check-subtasks 和 load-role
- `scripts/compact-context.sh` — 生成 context.compact.json，只保留当前任务完整信息 + 依赖摘要 + 队列统计 + 父/兄弟子任务信息
- `scripts/get-next-task-json.sh` — 获取下一个待执行任务的共享逻辑（Hook 和 Python 驱动器共用），自动跳过有子任务的父任务
- `scripts/lock-utils.sh` — 基于 mkdir 原子操作的文件锁，被其他脚本 source 引用
- `scripts/propagate-failure.sh` — 任务失败时批量标记下游依赖为 blocked
- `scripts/check-subtasks.sh` — 子任务状态联动：全部子任务 done → 父任务 done；任一子任务 failed → 父任务 failed
- `scripts/check-cycles.sh` — DFS 检测循环依赖
- `scripts/run_autonomy.py` — 替代驱动方式，外部 Python 进程循环调用 Claude CLI
- `templates/CLAUDE.autonomy.md` — Autonomy Protocol，定义 AI 执行任务的完整规范（含子任务拆分协议）
- `templates/agents/{architect,developer,tester}.md` — 三种角色提示词

### 子任务机制

任务支持父子关系。`add-task.sh --parent F001` 创建子任务（ID 格式 F001.1, F001.2）。父任务有子任务后不会被直接执行，由子任务驱动完成。子任务全部 done 时父任务自动标记 done，任一子任务 failed 时父任务标记 failed 并触发失败传播。

### 命令系统

`commands/*.md` 中的 10 个命令定义，安装时复制到 `~/.claude/commands/autocc/`，通过 `/autocc:*` 调用。命令中用 `${CLAUDE_PLUGIN_ROOT}` 占位符引用插件根目录，安装脚本用 sed 替换为实际路径。

## 开发约定

### Shell 脚本

- 所有脚本使用 `set -euo pipefail`
- JSON 操作统一用 jq，参数用 `--arg` 传递防注入
- 文件写入用临时文件 + mv 保证原子性
- 需要修改 feature_list.json 时必须通过 lock-utils.sh 加锁

### 安装与测试

```bash
# 安装（注册命令 + Stop Hook + 设置权限）
bash install.sh

# 卸载
bash uninstall.sh

# 手动测试通知
scripts/notify.sh task_done "测试通知"
```

无自动化测试套件。验证方式是在实际 Claude Code 会话中运行 `/autocc:*` 命令。

### Git 提交格式

任务执行时使用 conventional commit：`feat({task_id}): {title}`
