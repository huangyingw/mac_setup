# 分支职责

主线是 `integration`，各分支做完合入主线。

| 分支 | worktree | 职责 |
|---|---|---|
| `integration` | 仓库根 | 框架与主线：`install.sh` / `uninstall.sh` / `lib/common.sh`（入口、记账、备份、恢复原状）、`modules/10-base`（Homebrew、git、nvim、iTerm2、Chrome 的安装）、`repos.txt` 与 `local/`（密钥检查、公开 / 改回私有、快照导出机制）、规则文档、在 `mba` 上的整体演练 |
| `loadrc` | `worktrees/loadrc` | loadrc 域：`snapshots/loadrc.*`（从 loadrc 导出哪些文件、哪些子模块）、`modules/20-loadrc`（目标机上取快照并接好 zsh / tmux / nvim / iTerm2 配置，让 `clauderc` 的 multi-agent 工具能用） |
| `agents` | `worktrees/agents` | agent 域：`modules/30-agents`（安装 Claude Code 与 Codex，把 `~/.claude`、`~/.codex` 配成与参考机一模一样，含全局规则和技巧；先备份对方原有配置；卸载时清登录态） |
| `spokenly` | `worktrees/spokenly` | 语音输入域：`modules/40-spokenly`（安装 Spokenly 与本机转写服务、配置与参考机一致、按 16GB 内存的标准下载模型）、`snapshots/voice_input.*`（从 voice_input 仓库导出哪些文件） |
| `nomachine` | `worktrees/nomachine` | 远程图形连接域：NoMachine 模块（目标机上安装、配置成能从别的机器图形界面连过去；恢复原状时清干净） |
| `integration-p1` | `worktrees/integration-p1` | 目标机家目录下多出 `~/.homebrew`，清单里没有记，恢复原状后还在(由 integration 忙碌改道) |
| `loadrc-p1` | `worktrees/loadrc-p1` | 20-loadrc 模块的共用上级目录记账，与框架新定的统一做法不一致(由 loadrc 忙碌改道) |
| `integration-p2` | `worktrees/integration-p2` | 安装清单（AGENTS.md 第 3 节）里没有 `20-loadrc` 模块要装的几个依赖(由 integration 忙碌改道) |
| `integration-p3` | `worktrees/integration-p3` | AGENTS.md 第 3 节的清单里没有「本机转写服务」这一项(由 integration 忙碌改道) |
| `integration-p4` | `worktrees/integration-p4` | Homebrew 原来就有时，恢复原状后它的下载缓存里还留着我们装过的安装包(由 integration 忙碌改道) |
