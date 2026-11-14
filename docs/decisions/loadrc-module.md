# `20-loadrc` 模块：设计依据

2026-11-13。模块做的事：把 loadrc 的快照放到目标机 `~/loadrc`，接好 zsh / tmux / nvim / git / iTerm2 的配置，
让 `clauderc` 的 multi-agent 工具（交接、项目总台、各种巡查）能用。

相关文件：`modules/20-loadrc/{install.sh,uninstall.sh,zshrc}`、`snapshots/loadrc.{conf,include}`。

## 1. 快照里放什么

`huangyingw/loadrc` 永不公开（`AGENTS.md` 第 5 节），目标机拿到的是 `huangyingw/loadrc-snapshot`：
只含 `snapshots/loadrc.include` 列出的文件、不带历史。

**原则：只导目标机用得上的。** 漏导 = 目标机少个功能，看得见、能补；多导 = 泄露，收不回。
密钥检查工具查不出明文口令、内网地址这类东西，所以：

- `bashrc` / `vishrc` / `agentrc` / `iterm2rc` 这些「什么都往里放」的目录**逐个文件写**，不整目录导；
- 整目录导的只有内容单一的：`vimrc`、`gitrc`、`clauderc`、`tmuxrc`、`.git-templates`，并排除其中的测试和跨机同步脚本；
- 改动白名单后，除了脚本自带的密钥检查，还要人工看一遍新增的文件（内网地址、口令赋值、机器清单）。

各项的理由：

| 白名单项 | 为什么要 |
|---|---|
| `.pathrc` `.envrc` `.gitrc` `.shellrc` `.macosrc` `.gorc` | 访客版 `~/.zshrc` 逐个加载的 rc：PATH、环境变量、别名、`claude` / `codex` 两个启动函数 |
| `oh-my-zsh`（子模块） | zsh 框架 |
| `.tmux.conf` `.tmux/plugins/tpm` `tmuxrc` | tmux 配置、插件管理器、配置里调用的脚本 |
| `vimrc`（除测试） | vim / nvim 的全部配置和本地插件 |
| `@vimrc/.vim/bundle/vim-anyfold` `@…/vim-autoformat` | 这两个子模块匿名拉不到，文件直接并进快照 |
| `neovim/init.lua` `neovim/.config/nvim/lua` | nvim 入口和 lazy.nvim 的插件清单（`neovim` 子模块是私有的，只取这两处） |
| `update_project`（子模块） | vim 命令和 git 钩子用的项目索引脚本 |
| `gitrc`（除 `gbil.log`）`.git-templates` | 全局 git 配置、别名脚本、全局钩子 |
| `bashrc/*.sh` `vishrc/*.sh`（逐个） | 被 vim 命令、tmux 配置、git 别名调用到的脚本（按引用关系找出来的） |
| `clauderc`（除测试、两个跨机同步脚本） | multi-agent 工具本体 |
| `agentrc/*.json`（3 个） | 工具读的开关文件 |
| `converge/crontab_lock.sh` | 巡查脚本共用的锁 |
| `iterm2rc/*`（7 个） | iTerm2 标签染色守护进程和它的安装脚本 |

**增补办法**：在 `snapshots/loadrc.include` 加一行 → `SNAPSHOT_LOCAL_ONLY=1 local/snapshot.sh loadrc huangyingw/loadrc-snapshot`
在本地导出 → 看 `~/.cache/mac_setup/snapshots/loadrc` 里新增的文件 → 按第 6 节的办法在假的家目录里试装。

不带的：`keys`、`.ssh` 两个子模块（用户定的不公开）、含凭证的 rc、按主机名加载的 rc、各机器的运维脚本。

## 2. `~/.zshrc`：用模块自带的访客版，不用 loadrc 的

参考机的 `~/.zshrc` 会加载 `~/loadrc/.loadrc` 整条链。那条链在别人电脑上会做几件不该做的事：
每开一个 shell 重装一次 crontab、按主机名执行带 sudo 的命令（演练机主机名正好是 `mba`）、加载含凭证的文件。

所以 `modules/20-loadrc/zshrc` 是一份单独维护的版本，效果与参考机一致，差别只有：

- 不加载 `.loadrc`，只逐个加载快照里带过来的 6 个 rc；
- 不自动起 ssh-agent、不把这台机器上的私钥加进去；
- 命令历史单独记在 `~/.zsh_history_mac_setup`，不写进机主的 `~/.zsh_history`；
- 补全缓存放进 `~/loadrc` 里，不落在家目录；
- PATH 里去掉参考机才有的两段。

代价：参考机的 `.zshrc` 以后改了，这份要手工跟。

## 3. 各项配置怎么落位

- **软链接到 `~/loadrc`**：`~/.oh-my-zsh`、`~/.tmux`、`~/.tmux.conf`、`~/.vim`、`~/.vimrc`、`~/.gitconfig`、
  `~/.globalgitignore`、`~/.git-templates`；`~/.config/nvim` 是我们建的目录，里面两个软链接。
- **对方原有的先备份**：上面每个落点、`~/.zshrc`、nvim 的数据 / 状态 / 缓存目录、`~/.viminfo`，原来有就先挪进备份目录，卸载时放回。
- **共用的父目录**（`~/.config`、`~/.local`、`~/.local/share`、`~/.local/state`、`~/.cache`、`~/Library/LaunchAgents` 等）：
  原来没有才记一笔 `newdir`，原来就有不动。**不记成 `path`**：`path` 在恢复原状时是整个删掉的，
  会连带删掉别人后来放进去的东西——2026-11-13 演练机上 `spokenly` 模块就这样删掉了本模块的测试环境，反过来同理。
  用框架的 `ms_claim_dir` 记账，由主卸载脚本最后一步统一处理：空了才删，不空就留下并说出还剩什么（`modules/README.md` 第 3 条）。
  工具运行时会往里写的位置用 `ms_own_if_absent` 记上，否则上级目录空不下来。
- **工具运行时才会写的位置**（`~/.cache/loadrc`、`~/.agent_projects.list`、`~/.claude`、`~/.codex` 等）：安装时先记账。
  其中 `~/.claude`、`~/.codex` 是「原来没有才记」——巡查脚本每分钟跑一次、会往里写日志，
  不先记的话，它抢在 `30-agents` 之前把目录建出来，就会被当成「对方原有的」备份起来、卸载后留在机器上。

### nvim 插件

配置里的插件平时是第一次打开 nvim 时在后台装。安装脚本直接预装好（`nvim --headless "+Lazy! install"`），34 个。

插件清单里有 4 个地址是 Bitbucket 的 ssh 地址，目标机拉不到。它们在 GitHub 上都有公开的同一份，
安装时在 `~/.config/git/config` 里**只对这 4 个地址**做改写。没有把所有 `git@github.com:` 都改写成 https——
对方自己的仓库可能正用着 ssh 密钥，全局改写会影响到。

### 全局 git 配置和钩子

照参考机启用，包括全局钩子：**提交后自动 pull / push 到已配置的上游**（没有上游的分支不动，网络操作有超时）。
这是参考机的日常工作方式，multi-agent 协作也依赖它；面试时在对方仓库里提交会自动推送，脚本结束时的人工事项里有提醒。
钩子还会在被提交的仓库里生成项目索引文件（被全局忽略清单忽略，不会进提交），卸载**不会**逐个仓库去清——见第 5 节。

凭证：全局配置把 GitHub 凭证交给 `gh`，所以装 `gh`；登录是人工事项。对方原来没用 `gh` 时，卸载会清掉钥匙串里 `gh` 的登录。

### 定时任务

装 `clauderc/cc.cron` 里的巡查（交接卡住自动重发、会话卡在登录或选择框时处理、清孤儿进程等，11 条），
用和 `install_cc_cron.sh` 相同的标记块追加到 crontab，对方原有条目原样保留，卸载只摘这一块。
不装两条：自动升级 npm 装的 Codex、跨机汇总后改配置——那是给参考机那几台机器用的。

### iTerm2

参考机的 profile 基本是默认值，「配置」就是 `iterm2rc/install.sh` 做的事：标签染色守护进程和它依赖的几项设置。
安装前把 iTerm2 的设置整个导出存一份，卸载时放回；原来没有设置的，卸载时连设置文件一起删。
守护进程的 python 环境（`~/.local/iterm2-venv`）和它的锁文件都记账。守护进程要人工点一次「允许 python 控制 iTerm」，属尽力而为，
没点也不影响其余功能。

### 为什么不用 loadrc 现成的 `setup.sh`

用户 2026-11-13 说过可以参考、也可以改 `~/loadrc/setup.sh`。对照过它和它调用的 `deploy_configurations.sh`：
与 zsh / tmux / nvim / git 有关的软链接，本模块都覆盖了。没有直接调用它，因为它是整机装机脚本
（Docker、虚拟机、整份 crontab、Linux 的包），而且直接覆盖、不备份、不记账——在别人电脑上跑完没法恢复原状。
要让它适用就得把这些全拆掉，等于重写；所以落位逻辑写在本模块里，`setup.sh` 没有动。
它里面有、本模块没带的小项：`tig` 的配置、`.hgrc`、`~/setup.cfg`（面试用不上）。

## 4. 依赖

`tmux`、`python`、`gh`、`git-lfs`（Homebrew）。已经装了的不动、不记账；我们装的卸载时卸掉。

- `python`：系统自带的 `python3` 在没装命令行工具的机器上只是占位程序；装了命令行工具则是 3.9。
  `clauderc` 的脚本在 3.9 下能跑（hook 用到的 12 个脚本在 3.9.6 和 Homebrew 的版本下都空跑通过），
  但参考机用的是 Homebrew 的版本，目标机保持一致。访客版 zshrc 和 `cron-py.sh` 都把 `/opt/homebrew/bin` 排在前面。
- `git-lfs`：全局 git 配置把它设成了必需，没有的话检出带 LFS 文件的仓库会报错。

## 5. 卸载与已知残留

文件、目录、软链接由主卸载脚本按清单删除 / 放回。模块自己的 `uninstall.sh` 处理清单管不到的：
摘掉 crontab 里我们的块、按名字注销守护进程（不依赖配置文件还在——它是退出即重启的，
注销不掉会把刚删掉的 python 环境和日志重新建出来）并放回 iTerm2 设置、停掉从 `~/loadrc` 起来的进程（跳过卸载自己所在的进程链）、
清 `/tmp` 下这套工具的日志、锁和状态（按名字，只删当前用户的）、清 `gh` 的登录，最后处理 `newdir`。每一步都先看清单，不是本次安装记下的不碰（演练机上几个分支各用各的清单）。

已知不会清的：

- 全局 git 钩子在**被提交过的仓库里**生成的项目索引文件（`files.proj` 等，被全局忽略清单忽略）；
- 用我的身份做的提交、推送本身。

## 6. 调试：在参考机上用假的家目录试装

不必每次都上演练机。两个环境变量：

- `MS_LOADRC_URL=<本地快照目录>`：不从 GitHub 拉，用 `SNAPSHOT_LOCAL_ONLY=1` 导出的本地快照；
- `MS_LOADRC_SANDBOX=1`：只做落在 `$HOME` 里的事，跳过装软件、crontab、iTerm2、钥匙串。**卸载时也要带**，
  否则卸载会去动参考机自己的 crontab 和钥匙串。

做法：建一个临时目录当 `HOME`（可以预先放几个「对方原有的」文件），去掉 `XDG_*`、`TMUX` 等环境变量，
把 `lib/`、`uninstall.sh`、`modules/20-loadrc/` 拷到 `$HOME/.mac_setup/src/` 下（只放本模块，免得跑到别的模块的清理），
跑模块的 `install.sh`，再跑 `uninstall.sh`，比较前后的文件列表。2026-11-13 这样跑的结果是前后完全一致；
装完往 `~/.config`、`~/.local/share` 里放几个「别人的」文件再卸载，这些文件和它们所在的目录都留下了。

巡查脚本**不要**在假的家目录里跑：它们找 tmux 用的是系统级的 socket，会作用到参考机真实的会话上。

## 7. 与 `30-agents` 的衔接

- 顺序：`20-loadrc` 在前。`30-agents` 安装时若 `~/loadrc/clauderc/` 下有 git 过滤器安装脚本就会跑，快照里带着。
- `claude` / `codex` 两个命令是 `.shellrc` 里的函数，分别调 `clauderc/claude_wrapper.py`（本体找 `~/.local/bin/claude`）
  和 `clauderc/codex_wrapper.py`（本体从 PATH 里找）；访客版 zshrc 的 PATH 含 `~/.local/bin` 和 `/opt/homebrew/bin`。
- 两份配置里的 hook 和状态栏引用 `~/loadrc/clauderc/` 下 17 个脚本，快照里全有。
