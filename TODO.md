# claude-autonomy 优化清单

## 高优先级

- [x] **progress.txt 轮转机制** — append-only 会无限增长，浪费 token。加轮转，只保留最近 N 条，历史归档到 progress.archive.txt
- [x] **失败依赖传播** — 当依赖的任务 failed 时，自动将下游任务标记为 blocked 并记录原因
- [x] **Shell 脚本健壮性** — 补 `set -euo pipefail`；jq 用 `--arg` 传参防注入；Stop Hook 中 sed 解析改用 jq

## 中优先级

- [x] **并发安全** — 用 mkdir 原子锁给 feature_list.json 加文件锁，防止并发写入损坏
- [x] **循环依赖检测** — next-task.sh 中检测循环依赖，给出明确提示
- [x] **断点恢复验证** — 恢复 in_progress 任务前，先检查 git status 确认代码状态一致
- [x] **Python 驱动器与 Hook 逻辑去重** — 抽取 get-next-task-json.sh 共享脚本，各处优先调用

## 低优先级

- [x] **补充任务管理命令** — 添加 edit、remove 命令
- [x] **完成后收尾动作** — 所有任务完成后输出总结
- [x] **插件分发与兼容性** — 添加 README；更新 SKILL.md 新命令；版本升至 1.1.0
