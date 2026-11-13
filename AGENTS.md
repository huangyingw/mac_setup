# mac_setup 项目规则

## 1. 项目目的

去 onsite 面试时，对方会给一台 Mac 让我读代码 / 写代码，但那台机器上没有我需要的环境。
本项目的目的：**在对方的 Mac 上快速把我需要的环境装好、配好**。

验收标准是能像演示项目 `/Volumes/workdata/myproject/git/tools/multi_agents_demo`（说明见其 `README.md`）里那样工作：

- 有**语音输入**；
- 能做 **multi-agent 协作**（交接、项目总台等 `~/loadrc` 里的那套工具）；
- **Claude Code 与 Codex 的配置和参考机一模一样**，包括全局规则和技巧（skills）。

## 2. 机器角色

| 角色 | 机器 | 说明 |
|---|---|---|
| 参考机 | 本机 `studio` | 一切以它现在的环境为准：装什么、怎么配，照它来 |
| 目标机 | `mba` | 代表「对方的电脑」，脚本在它上面跑 |

目标机连接方式：

- `ssh mba.local`，用户名 `huangyingw`；
- 参考机的 SSH 公钥（`~/.ssh/id_rsa.pub`）已于 2026-11-13 装进目标机的 `authorized_keys`，**免密登录**；
- 目标机上 `sudo` 不需要密码。

目标机基线（2026-11-13 实测）：macOS 26.6.2，arm64；`/Applications` 里只有 Safari；没有 Homebrew、没有 Xcode 命令行工具（`/usr/bin/git` 只是占位，真用会触发安装提示）、没有 `~/loadrc` / `~/.claude` / `~/.codex`。安装脚本必须能从这种干净系统起步。

## 3. 要装的东西

清单以本节为准。用户说过「可能还会继续补充」——**新增一项先登记到这张表，再动手**。

| 项 | 参考机上的现状（2026-11-13） |
|---|---|
| Spokenly（语音输入） | `/Applications/Spokenly.app`，2.34.1；Homebrew 有 cask `spokenly` |
| iTerm2 | `/Applications/iTerm.app` |
| git | Homebrew，`/opt/homebrew/bin/git` |
| nvim | Homebrew `neovim` 0.12.6 |
| `~/loadrc/` | GitHub `huangyingw/loadrc`（私有），带一批子模块 |
| Claude Code | 配置在 `~/.claude`，即 GitHub `huangyingw/claude-config`（私有） |
| Codex | 配置在 `~/.codex`，即 GitHub `huangyingw/codex-config`（私有） |
| Chrome | `/Applications/Google Chrome.app` |

## 4. 硬约束

1. **🚫 不能在两台机器之间直接拷贝任何文件**——那是人家的电脑。`scp` / `rsync` / `sftp` / 经 ssh 管道把文件内容传过去，都不行。
2. **唯一的例外是 SSH 公钥**：只为了免密登录、方便远程操作（已完成，见第 2 节）。
3. `ssh` 到目标机**只用来执行命令**（跑脚本、看结果、排查），不用来搬内容。
4. **所有内容一律走 GitHub**：参考机上提交并推送 → 目标机上 `clone` / `pull` → 在目标机上运行脚本完成安装配置。
5. **🚫 密码、令牌等任何凭证不进仓库**（文档、脚本、提交说明都不行）——本仓库在安装窗口期会被改成公开。目标机的登录密码因此没有写进本文档。

## 5. 公开 / 私有切换流程

目标机上没有我的 GitHub 凭证，所以私有仓库拉不下来。约定流程：

1. 参考机：把安装需要的那几个 GitHub 仓库改成 **public**；
2. 目标机：`clone` 并运行安装脚本；
3. 参考机：安装完成后跑一个脚本，把这些仓库改回 **private**。

规矩：

- 要切换的仓库写成**显式清单**放在仓库里，「改公开」和「改回私有」两个脚本读同一份清单，不靠记忆；
- 「改回私有」脚本跑完必须**逐个核对**可见性，确认全部回到 private 才算结束；
- 公开窗口尽量短：装完立刻改回。

相关仓库当前都是私有（2026-11-13 实测）：`huangyingw/mac_setup`（本仓库）、`huangyingw/loadrc`、`huangyingw/claude-config`、`huangyingw/codex-config`、`huangyingw/neovim`。到底哪几个需要公开，实现时确定后写进清单。

参考机上已有单仓库的切换脚本可参考：`~/loadrc/gitrc/toggle-github-visibility.sh`。

## 6. 待定事项

下面几条是写这份文档时发现、还没有结论的问题（由 agent 提出，不是用户的决定）：

- **公开前的密钥检查**：`loadrc` 等仓库历史很长，改公开等于把整个提交历史暴露出去，公开后可能被缓存或抓取，改回私有也收不回。改公开之前需要先确认仓库（含历史）里没有密钥 / 密码。
- **私有子模块**：`loadrc` 的子模块里有不在 GitHub 上的（如 Bitbucket 的 `keys`）和不该公开的（如 `.ssh`）。目标机上需要哪些子模块、不需要的怎么跳过，待定。
- **登录态**：Claude Code、Codex、Chrome、Spokenly 的账号登录不随仓库走，需要在目标机上人工登录；哪些步骤无法自动化，实现时列出来。
- **真实面试场景**：真到对方电脑上时，没有参考机在旁边 ssh 过去操作，安装应当能在目标机上用一条命令独立跑完；`mba` 上经 ssh 操作只是演练手段。
- **事后清理**：面试结束后是否需要一个把对方电脑恢复原状的卸载脚本（尤其是登录态），待用户决定。
