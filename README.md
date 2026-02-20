# claude-autonomy

Claude Code 自主开发插件 — 基于文件状态机的"轮班工人"模式，让 AI 无人值守地逐个完成任务队列。

## 安装

将此目录放到你的 Claude Code 插件路径下，或在项目中引用：

```bash
# 方式一：符号链接到全局插件目录
ln -s /path/to/claude-autonomy ~/.claude/plugins/claude-autonomy

# 方式二：在项目 .claude/plugins.json 中引用
```

依赖：`jq`（`brew install jq`）

## 快速开始

```bash
# 1. 初始化
/autocc:init my-project

# 2. 用自然语言描述需求，AI 自动拆解任务
/autocc:plan 做一个用户系统，包括注册、登录、个人资料编辑，需要JWT认证

# 3. 或手动添加单个任务
/autocc:add "用户登录" "实现 JWT 登录接口" --priority 1 --criteria "返回 token" "错误处理"

# 3. 查看状态
/autocc:status

# 4. 执行单个任务
/autocc:next

# 5. 或启动自主循环
/autocc:run --max-iterations 10
```

## 命令

| 命令 | 说明 |
|------|------|
| `/autocc:init [name]` | 初始化自主系统 |
| `/autocc:plan <需求描述>` | AI 自动分析需求并拆解为任务 |
| `/autocc:add "title" "desc" [opts]` | 手动添加单个任务 |
| `/autocc:edit <id> [--title/--desc/--priority/--status]` | 编辑任务 |
| `/autocc:remove <id> [--force]` | 删除任务 |
| `/autocc:status` | 查看状态 |
| `/autocc:next` | 执行下一个任务 |
| `/autocc:run [--max-iterations N]` | 启动自主循环 |
| `/autocc:stop` | 停止循环 |

## 工作原理

1. AI 作为无记忆的"轮班工人"，每次会话从文件恢复上下文
2. `.autonomy/feature_list.json` 管理任务队列和状态
3. `.autonomy/progress.txt` 作为会话间的交接日志（自动轮转，超限归档至 `progress.archive.txt`）
4. Stop Hook 拦截退出，自动加载下一个任务
5. 任务失败时自动传播，阻塞下游依赖

## 安全机制

- **并发安全** — 基于 mkdir 原子操作的文件锁，防止并发写入损坏 `feature_list.json`
- **循环依赖检测** — DFS 遍历任务依赖图，发现循环时给出明确提示
- **断点恢复** — 恢复 `in_progress` 任务前检查 `git status`，确认代码状态一致
- **依赖验证** — 添加任务时校验依赖 ID 是否存在，无效 ID 直接报错
- **失败传播** — 任务失败后批量标记下游依赖为 `blocked`，避免无效执行

## 替代运行方式

除了 Stop Hook，还可以用 Python 外部驱动器：

```bash
python scripts/run_autonomy.py --max-iterations 10 --cooldown 5 --model opus
```

## License

MIT
