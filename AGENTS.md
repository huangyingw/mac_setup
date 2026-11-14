# mac_setup 项目规则

## 1. 项目目的

去 onsite 面试时，对方会给一台 Mac 让我读代码 / 写代码，但那台机器上没有我需要的环境。
本项目的目的：**在对方的 Mac 上快速把我需要的环境装好、配好**。

验收标准是能像演示项目 `/Volumes/workdata/myproject/git/tools/multi_agents_demo`（说明见其 `README.md`）里那样工作：

- 有**语音输入**；
- 能做 **multi-agent 协作**（交接、项目总台等 `~/loadrc` 里的那套工具）；
- **Claude Code 与 Codex 的配置和参考机一模一样**，包括全局规则和技巧（skills）。

**🎯 真实场景决定设计（用户 2026-11-13 确认，必须遵守）**：真到对方电脑上时，**没有参考机在旁边 ssh 过去操作**。因此：

- 安装必须能**在目标机上用一条命令独立跑完**（打开终端、贴一行命令），不依赖参考机、不依赖 ssh；
- 在 `mba` 上经 ssh 操作**只是演练手段**；任何「只有从参考机 ssh 过去才能完成」的步骤都算缺陷；
- 目标机上必须人工做的事（账号登录、系统权限授权等）要在脚本结束时**逐条列出来**，不能悄悄跳过。

**🚫 一切都由仓库里的脚本自动安装，不手工安装（用户 2026-11-13 定）**：目的是 onsite 面试时**快速、一次性**把需要的东西都搞好。

- 第 3 节清单里的每一项——包括 Homebrew、git、nvim、iTerm2、Chrome 这些基础工具——连同它们的配置，都必须由本仓库的脚本装好（`install.sh` → `modules/*/install.sh`）；
- **演练时也一样**：在 `mba` 上发现缺东西、配置不对，改脚本、推送、重跑，**不许 ssh 过去手工装一下、改一下了事**——手工弄上去的东西到了真实场景不会出现；
- 只有脚本确实做不了的（账号登录、系统权限授权）才算人工步骤，并且必须由脚本在结尾列出来；
- 验收方式：从干净系统跑那一条命令，跑完即可用；演练机上任何「不是脚本装的」东西都算缺陷。

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
| 本机转写服务（Spokenly 听写实际用的模型在这里） | `mlx_audio.server`（mlx-audio 0.5.7），由 launchd（`com.huangyingw.qwen3-asr`）登录即拉起，监听 `127.0.0.1:8765`；目录 `~/.local/share/qwen3-asr-server`（Python 3.12 环境 + 模型 + 日志，5.1G）；模型 `Qwen3-ASR-1.7B-bf16`；来源是 GitHub `huangyingw/voice_input`（私有） |
| uv（建转写服务的 Python 环境用） | Homebrew `uv` 0.13.7 |
| iTerm2 | `/Applications/iTerm.app` |
| git | Homebrew，`/opt/homebrew/bin/git` |
| nvim | Homebrew `neovim` 0.12.6 |
| `~/loadrc/` | GitHub `huangyingw/loadrc`（私有），带一批子模块 |
| Claude Code | 配置在 `~/.claude`，即 GitHub `huangyingw/claude-config`（私有） |
| Codex | 配置在 `~/.codex`，即 GitHub `huangyingw/codex-config`（私有） |
| Chrome | `/Applications/Google Chrome.app` |
| NoMachine（远程图形界面连接） | `/Applications/NoMachine.app`，9.10.3；Homebrew cask `nomachine`（2026-11-13 补登记） |
| tmux | Homebrew `tmux` 3.8；agent 会话都跑在 tmux 里（`20-loadrc` 装） |
| python | Homebrew `python@3.15` 3.15.2；`clauderc` 的脚本用，系统自带的 `python3` 在干净系统上只是占位程序（`20-loadrc` 装） |
| gh | Homebrew `gh` 2.103.3；全局 git 配置把 GitHub 凭证交给它，登录是人工事项（`20-loadrc` 装） |
| git-lfs | **参考机没装**；全局 git 配置把它设成了必需，不装的话检出带 LFS 文件的仓库会报错，所以目标机上装（用户 2026-11-13 定；`20-loadrc` 装） |
| 定时巡查 | 参考机 crontab 里 `clauderc/cc.cron` 那一套；目标机上往当前用户的 crontab 追加带标记的一块（11 条：交接卡住自动重发、会话卡在登录或选择框时处理、清孤儿进程等），对方原有条目保留，卸载只摘这一块（`20-loadrc` 装） |

各项的补充要求（用户 2026-11-13 定）：

- **Spokenly**：不需要登录；要**安装**、把配置做成和参考机**一模一样**、并**下载好语音模型**。模型按 `mbp` 的标准选——即按 **16GB 内存**的机器选合适的模型（参考机 `studio` 是 64GB，不能直接照搬它的模型选择；`mba` 也是 16GB）。
- **本机转写服务**（2026-11-13 补登记——`40-spokenly` 模块做完之后才登记的，顺序上晚了）：参考机上 Spokenly 的听写模型不是它内置的，而是指向这套本机服务，所以上一条的「下载好语音模型」落到实处就是**把这套服务连同模型一起装好**。目标机上装的是：Homebrew 的 `uv`、服务目录 `~/.local/share/qwen3-asr-server`（Python 环境、依赖、模型、日志都收在里面，约 3.8G）、16GB 档的模型 `Qwen3-ASR-0.6B-8bit`、一个 launchd 配置。`voice_input` 本身不公开（里面有个人口述的转写文本），只经快照 `huangyingw/voice_input-snapshot` 公开模块用到的几个文件（白名单 `snapshots/voice_input.include`）。只支持 Apple 芯片。详见 `docs/decisions/spokenly.md`。
- **NoMachine**（用户 2026-11-13 提出）：在目标机上安装**并配置好**，让用户能从别的机器用图形界面连过去看实际效果。它是对外开放的远程访问服务，真实面试时是否默认装、恢复原状时要清掉哪些东西，由负责的分支调查后报给用户定。
- **登录态**：Claude Code、Codex、Chrome 的账号登录不随仓库走，在目标机上**人工登录**。

## 4. 硬约束

1. **🚫 不能在两台机器之间直接拷贝任何文件**——那是人家的电脑。`scp` / `rsync` / `sftp` / 经 ssh 管道把文件内容传过去，都不行。
2. **唯一的例外是 SSH 公钥**：只为了免密登录、方便远程操作（已完成，见第 2 节）。
3. `ssh` 到目标机**只用来执行命令**（跑脚本、看结果、排查），不用来搬内容。
4. **所有内容一律走 GitHub**：参考机上提交并推送 → 目标机上 `clone` / `pull` → 在目标机上运行脚本完成安装配置。
5. **🚫 密码、令牌等任何凭证不进仓库**（文档、脚本、提交说明都不行）——本仓库在安装窗口期会被改成公开。目标机的登录密码因此没有写进本文档。

## 5. 公开 / 私有切换流程

目标机上没有我的 GitHub 凭证，所以私有仓库拉不下来。约定流程：

1. 参考机：`local/publish.sh` 把 `repos.txt` 里的仓库改成 **public**（改之前自动做密钥检查）；
2. 目标机：一条命令拉取并运行安装脚本；
3. 参考机：安装完成后 `local/unpublish.sh` 把这些仓库改回 **private**，并逐个核对。

规矩：

- **`repos.txt` 是唯一清单**，两个脚本读同一份，不靠记忆；只登记平时是 private 的仓库；
- **改公开之前必须先做密钥检查**（用户 2026-11-13 同意）：扫描仓库在 GitHub 上的完整提交历史，确认没有密码 / 密钥才能改公开——公开后可能被缓存或抓取，改回私有也收不回。检查不过，一个仓库都不改；
- **🚫 `huangyingw/loadrc` 本身永远不公开**：2026-11-13 的检查没有通过（问题在提交历史里）。它只能经 `local/snapshot.sh` 导出「只含需要的文件、不带历史」的快照到 `huangyingw/loadrc-snapshot`，公开的是快照。导出范围用白名单 `snapshots/loadrc.include`；
- **`loadrc` 的 `keys` 和 `.ssh` 两个子模块不公开**（用户 2026-11-13 定），安装流程必须在没有它们的情况下正常工作；
- 「改回私有」跑完必须看到**全部确认是 private** 才算结束；
- 公开窗口尽量短：装完立刻改回；
- 本仓库的文档、提交说明里**不写任何仓库里具体查出了什么密钥**（本仓库自己也会公开）。

设计依据见 `docs/decisions/architecture.md`，分支职责见 `BRANCHES.md`，模块怎么写见 `modules/README.md`。

## 6. 备份与事后清理

用户 2026-11-13 定：

- **装之前先备份对方电脑里的现有配置**：凡是安装会覆盖或改动的东西（例如已有的 Claude Code 配置 `~/.claude`、Codex 配置 `~/.codex`，以及 shell / nvim / tmux 等配置），动之前先备份，不能直接覆盖。
- **需要一个卸载脚本**：面试结束后把对方电脑**恢复原状**——删掉我们装的东西、清掉登录态、把备份的原有配置放回去。
- 由此推出的实现要求：安装过程要**记账**（哪些是我们装的、哪些是原来就有的），卸载时只删我们装的，**原来就有的软件和配置不能动**。
