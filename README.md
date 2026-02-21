# claude-autonomy

Claude Code 自主开发插件 — 基于文件状态机的"轮班工人"模式，让 AI 无人值守地逐个完成任务队列。

## 安装

```bash
# 1. 克隆仓库
git clone https://github.com/bigccc/claude-autonomy.git
cd claude-autonomy

# 2. 一键安装（安装命令 + 注册 Stop Hook + 设置权限）
bash install.sh
```

安装脚本会自动完成：
- 将 `/autocc:*` 命令安装到 `~/.claude/commands/autocc/`
- 注册 Stop Hook 到 `~/.claude/settings.json`（自主循环的核心机制）
- 设置所有脚本的可执行权限

重启 Claude Code 即可使用。

卸载：`bash uninstall.sh`

依赖：`jq`（`brew install jq`）

## 快速开始

```bash
# 1. 初始化
/autocc:init my-project

# 2. 用自然语言描述需求，AI 自动拆解任务
/autocc:plan 做一个用户系统，包括注册、登录、个人资料编辑，需要JWT认证

# 3. 或手动添加单个任务
/autocc:add "用户登录" "实现 JWT 登录接口" --priority 1 --criteria "返回 token" "错误处理"

# 3b. 添加带角色的任务
/autocc:add "设计认证架构" "设计 JWT 认证系统架构" --role architect --priority 1

# 3c. 用 --team 自动生成多角色流水线
/autocc:plan --team 做一个用户系统，包括注册、登录、个人资料编辑

# 4. 查看状态
/autocc:status

# 5. 执行单个任务
/autocc:next

# 6. 或启动自主循环
/autocc:run --max-iterations 10
```

## 命令

| 命令 | 说明 |
|------|------|
| `/autocc:init [name]` | 初始化自主系统 |
| `/autocc:plan <需求描述> [--team]` | AI 自动分析需求并拆解为任务（--team 生成多角色流水线） |
| `/autocc:add "title" "desc" [opts]` | 手动添加任务（支持 --role architect/developer/tester） |
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
- **超时保护** — 任务执行超过 `task_timeout_minutes`（默认 30 分钟）自动标记失败，防止 AI 卡死
- **Webhook 通知** — 任务完成/失败/超时/全部完成时发送飞书/钉钉/企业微信通知
- **智能裁剪上下文** — 自动生成精简的 `context.compact.json`，只保留当前任务完整信息和队列摘要，大幅减少 token 消耗
- **Agent 角色系统** — 支持 architect/developer/tester 三种角色，不同任务由不同角色提示词驱动，提升任务执行质量
- **Team 自动流水线** — `/autocc:plan --team` 自动生成架构师→开发者→测试者的多角色任务流水线

## 通知配置

任务完成、失败、超时、全部完成时自动发送通知。在 `.autonomy/config.json` 中配置 `notify_type` 和 `notify_webhook` 两个字段。`notify_webhook` 留空则不发送通知。

手动测试：`scripts/notify.sh task_done "测试通知"`

### 飞书 (Feishu)

1. 在飞书群中添加「自定义机器人」，获取 Webhook 地址
2. 配置：

```json
{
  "notify_type": "feishu",
  "notify_webhook": "https://open.feishu.cn/open-apis/bot/v2/hook/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

### 钉钉 (DingTalk)

1. 在钉钉群中添加「自定义机器人」，安全设置选择「自定义关键词」，添加关键词 `任务`（通知内容包含此关键词）
2. 复制 Webhook 地址，配置：

```json
{
  "notify_type": "dingtalk",
  "notify_webhook": "https://oapi.dingtalk.com/robot/send?access_token=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
}
```

### 企业微信 (WeCom)

1. 在企业微信群中添加「群机器人」，获取 Webhook 地址
2. 配置：

```json
{
  "notify_type": "wecom",
  "notify_webhook": "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

### Server酱 (ServerChan)

1. 前往 [sct.ftqq.com](https://sct.ftqq.com/) 登录获取 SendKey
2. SendKey 有两种格式：`SCTxxxxxxxx`（旧版）或 `sctpNNNtXXXXXX`（Turbo 版），脚本自动识别对应的推送 URL
3. 配置时 `notify_webhook` 填写 SendKey（不是 URL）：

```json
{
  "notify_type": "serverchan",
  "notify_webhook": "SCTxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
}
```

Turbo 版示例：

```json
{
  "notify_type": "serverchan",
  "notify_webhook": "sctp168tXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
}
```

Server酱支持在微信、企业微信、钉钉、飞书等多个通道同时接收消息，具体通道在 Server酱控制台配置。

## 替代运行方式

除了 Stop Hook，还可以用 Python 外部驱动器：

```bash
python scripts/run_autonomy.py --max-iterations 10 --cooldown 5 --model opus
```

## License

MIT
