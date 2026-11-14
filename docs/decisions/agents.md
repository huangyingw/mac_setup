# agents 域：Claude Code 与 Codex

记录日期：2026-11-13。对应 `modules/30-agents/`。规则见仓库根 `AGENTS.md`，这里记「为什么这样做」和验证到了哪一步。

## 1. 参考机现状（调查结论）

| 项 | 参考机 | 目标机上的做法 |
|---|---|---|
| Claude Code 本体 | 官方原生安装器，`~/.local/bin/claude` → `~/.local/share/claude/versions/<版本>`，自动更新开着 | 同样用官方安装器，装最新版 |
| Codex 本体 | nvm 的 node 下 `npm -g` 装的 `@openai/codex` | Homebrew cask `codex` |
| `~/.claude` | `huangyingw/claude-config` 的检出，`integration` 分支（仓库默认分支是 `master`，落后很多，不能用） | 匿名 `git clone --branch integration` |
| `~/.codex` | `huangyingw/codex-config` 的检出，`integration` 分支 | 同上 |
| 启用的插件 | `gopls-lsp`、`swift-lsp`（官方插件市场）；下载内容不在配置仓库里 | 按 `settings.json` 的 `enabledPlugins` 补装 |

## 2. 几个取舍

- **Claude Code 必须用官方安装器**：loadrc 的 `claude_wrapper.py` 把本体位置写死为 `~/.local/bin/claude`，换成 Homebrew 的 cask 会找不到。
- **Codex 用 Homebrew 而不是 npm**：loadrc 的包装脚本在 PATH 等几处找 `codex`，不挑安装方式；cask 与参考机是同一个版本，不用先装 node，卸载由框架记账处理。它卸载时附带的清理只删**空的** `~/.codex`，不会碰放回去的原件。
- **先拉配置、再装本体**：安装器和工具首次启动都会往 `~/.claude` 写东西，目录必须已经是我们的检出。配置仓库先拉到临时目录，成功了才挪走对方原有的目录——仓库没公开时安装会失败，但不会把对方的配置挪走后留个空。
- **插件装完把 `settings.json` 原样放回**：「添加插件市场」会往 `settings.json` 加一段参考机没有的内容。市场另有文件记着，放回后插件照常启用，文件与参考机一致。
- **`~/.claude.json` 只预置一个开关**（`resumeReturnDismissed`）：参考机的 `settings.json` 里注明这个开关只在该文件里生效。其余内容由 Claude Code 自己生成。

## 3. 与参考机不一样、也不打算一样的地方

这些都不在配置仓库里，是每台机器自己的状态：

- **账号登录**：人工做，脚本结束时列出。
- **模型与思考强度的选择**：参考机的选择被 git 过滤器挡在仓库之外（设计如此，各机独立），目标机用工具的默认值，登录后用 `/model` 自己选。
- **Codex 的本机段**（项目信任、hook 信任台账等）：Codex 运行时自己写。
- **账号侧下发的技巧和插件**：登录后自动同步。

## 4. 备份与恢复原状

记账的路径：`~/.claude`、`~/.codex`、`~/.claude.json`、`~/.local/bin/claude`、`~/.local/share/claude`、`~/.local/state/claude`、`~/.cache/claude`、`~/Library/Caches/claude-cli-nodejs`、`~/.cache/codex-runtimes`、各浏览器的「本机消息」清单。对方原有的同名东西先挪进备份，卸载时放回。

共用的上级目录（`~/.local` 及其 `bin` / `share` / `state`、`~/.cache`）按框架约定用 `ms_claim_dir` 记：原来没有才建、才记账，恢复原状时空了才删，别人后放进去的东西不碰。

「本机消息」清单不只写给 Chrome：参考机上两个工具给 Chrome、Chrome for Testing、Chromium、Brave、Arc、Edge、Vivaldi、Opera 都写了，没装的浏览器也被建出了只放这份清单的数据目录。所以这些浏览器的 `NativeMessagingHosts` 目录都按共用目录记（安装时先建出来，卸载时空了才删），里面的两份清单记为我们的。

清单管不到、放在模块自己的 `uninstall.sh` 里的：

- 停掉我们装的工具还在跑的进程（否则目录删掉后会被重新写出来）；
- `~/.claude.json` 的伴生文件（`.backup`、`.tmp.*`，名字不固定）：安装时把对方原有的挪进备份，卸载时清掉期间产生的；
- **钥匙串里的登录**。Claude Code 的登录记在钥匙串服务 `Claude Code-credentials`；Codex 默认记在 `~/.codex/auth.json`，配成 keyring 时用 `Codex Auth`。第一次安装时在清单里记一行 `keychain`：
  - `ours`（原来没有）→ 卸载时删掉；
  - `saved`（原来有，已存一份到备份目录，权限 600）→ 卸载时删掉我的、放回原来的；
  - `lost`（原来有，没存下来）→ 卸载时删掉我的，并在安装结束时提示「要提前告诉机主之后得重新登录」。

对方原来就有的 Claude Code / Codex 本体不动、不记账。

## 5. 依赖 loadrc 域的部分

`settings.json` 与 `hooks.json` 里的 hooks、状态栏全部指向 `~/loadrc/clauderc/`；`claude` / `codex` 命令本身是 loadrc 的 shell 函数；`~/.local/bin` 和 Homebrew 进 PATH 也靠 loadrc 的 zsh 配置。没有 `~/loadrc` 时本模块照常装完并给出提示，但 hooks 会报找不到脚本。两个配置仓库的 git 过滤器安装脚本也在 loadrc 里，有就跑一次，没有不影响使用。

## 6. 验证记录（2026-11-13，目标机 `mba`）

用独立的状态目录演练（`MS_HOME=~/.mac_setup_agents`），不动其他分支共用的 `~/.mac_setup`。

| 场景 | 结果 |
|---|---|
| 干净系统上安装 | Claude Code 2.1.325、Codex 0.169.0，与参考机同版本；`~/.claude`、`~/.codex` 的提交与参考机相同，`git status` 干净；两个插件已启用 |
| 重跑安装 | 不报错、不重复备份 |
| 恢复原状（干净场景） | 家目录、`~/Library` 下的缓存 / 设置 / 支持目录、已装 cask、钥匙串服务名，与安装前的清单逐行一致 |
| 机主原来就有 `~/.claude`、`~/.codex`、`~/.claude.json`、`~/.local/bin` 里的东西 | 安装时全部备份；恢复后原有文件校验和逐个一致 |
| 钥匙串登录的备份 / 清除 / 放回 | 在参考机上用假服务名对真实的 `security` 走通了「原来没有」「原来就有」两种情况 |
| 共用目录里有别人的东西（改用 `ms_claim_dir` 后） | 装完往 `~/.local/bin`、`~/.local/state`、`~/.cache`、Vivaldi 的 `NativeMessagingHosts` 里各放一份别人的文件，恢复原状后都还在，所在目录保留并说出剩下什么；本模块的东西删干净（演练期间 Spokenly 域往我建的 `~/.local/share` 里装了东西，也照样保留） |
| 与参考机逐项对照（最终代码） | 两个工具的版本、两份配置的提交号、技巧数（17 / 7）、hooks 命令条数（31 / 10）都相同 |

演练时要留意的两件事：

- **演练机是几个分支共用的**。最后一轮对比清单时多出 4 个路径，逐个核对都不是本模块留下的（Spokenly 域当时正在装，另一个是 Homebrew 自己的 `~/.homebrew`——把它指到临时目录后单独装卸一次 Codex，确认这一步不会写它）。本模块记账的路径和钥匙串项逐个确认已清。
- **推送后马上用 `MS_REFRESH=1` 可能取到旧代码**：GitHub 的压缩包在推送后十几秒内还是上一个提交。演练前先看一眼下载到的模块是不是新的。

没有验证到的：

- **真实登录之后的清理**。经 ssh 进去的会话不能写登录钥匙串，登录也只能人工做，所以「登录 → 恢复原状 → 登录态确实没了」要在目标机本机终端里人工走一遍。
- **hooks 实际运行**。要等 `20-loadrc` 模块把 `~/loadrc` 放好。
