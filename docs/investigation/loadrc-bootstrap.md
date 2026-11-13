# 调查：在干净的 Mac 上部署 loadrc 需要什么

调查日期：2026-11-13，对象是参考机 `~/loadrc`（主线 `origin/integration`）、`~/.claude`、`~/.codex`。
只读调查的结论，**未在目标机上实测**；标「未确认」的需要实现时验证。路径相对 `~/loadrc`。

## 结论

1. **loadrc 现成的装机入口不能直接用**。`setup.sh` 面向 Linux，mac 段清单陈旧（约 50 个无关 formula、缺 neovim / python / node），末尾的 `submodule_setup.sh` 还会尝试 push。没有 Brewfile。可参考的最小软链集合在 `osxrc/linuxdisk.sh` L292-305。
2. **nvim 的配置在私有子模块 `neovim` 里**（`init.lua`、`.config/nvim/lua/*`、`install.sh`、`post.sh`）。fork 里的 C 源码运行时用不到（mac 上用 Homebrew 的 nvim）。拿不到这个仓库，nvim 就没有配置。
3. **仓库里没有处理 `git@` 地址的机制**（没有 `insteadOf`）。子模块和部分 lazy 插件的地址是 `git@github.com:` / `git@bitbucket.org:`，目标机没有密钥，拉不到。
4. **loadrc 的 shell 启动链有不适合别人电脑的副作用**（见下）。

## 最小依赖（推断）

- Homebrew：必需 `git`、`tmux`、`neovim`、`python`、`node`；建议 `ripgrep`、`jq`、`gh`、`git-lfs`（`gitrc/.gitconfig` 设了 lfs `required=true`，且 github 的 credential helper 指向 `gh`）。
- 没装 Xcode 命令行工具时，`/usr/bin/git`、`/usr/bin/python3`、`make` 都只是占位程序。
- `clauderc` 的 Python 脚本几乎只用标准库；agent 跑在 tmux 里的 nvim `:terminal` 中。

## 子模块

`.gitmodules` 有 29 条，index 里实际有 24 个 gitlink。

| 子模块 | 判断 | 说明 |
|---|---|---|
| `neovim` | 必需 | 私有 fork，nvim 配置所在 |
| `oh-my-zsh` | 必需 | `.zshrc` 依赖；fork 是公开的，也可换上游 |
| `.tmux/plugins/tpm` | 必需 | https 地址；`.tmux.conf` 缺插件时会自动用 https 拉 |
| `vimrc/.vim/bundle/vim-anyfold` | 实际必需 | 地址在 Bitbucket；`vimrc/.vimrc` 对多种文件类型自动调用它，缺了打开文件可能报错（推断） |
| `vimrc/.vim/bundle/vim-fugitive` | 强烈建议 | 公开 fork，git 相关命令大量依赖 |
| `vim-autoformat`（Bitbucket）、`bufexplorer`、`LargeFile`、`vim-fetch`、`tig-explorer.vim` | 可选 | |
| `update_project`、`cscope` | 可选 | 缺了相应功能静默失效 |
| `keys`、`.ssh` | 不需要、不公开 | 缺 `keys` 不报错；缺 `~/.ssh` 目录会报错，见下 |
| 其余（jdupes、rsync、sshfs、plantumlmacviewer 等） | 不需要 | 与本项目目标无关的独立工具 |

不是子模块、由 lazy 拉取的插件里，有 4 个用 `git@bitbucket.org` 地址（`neovim/.config/nvim/lua/plugins.lua` L288-293），无凭证时同步会报错，都属可选。

## 不适合别人电脑的副作用

- **每开一个 shell 都会重装 crontab**：`.loadrc` L27 调 `crontabrc/install.sh`，会写入每分钟运行的任务，以及 `clauderc/cc.cron` 里约 13 条 watchdog。macOS 首次写 crontab 是否弹授权框：未确认。
- **按主机名加载 `.<hostname>.rc`**（`.loadrc` L20-25）：主机名是 `studio` / `mba` / `macmini` / `mbp2` 时，每个 shell 都会执行带 `sudo` 的命令。**演练机的主机名正是 `mba`**，对方的电脑则不会命中——演练结果会与真实场景不同。
- **没有 `~/.ssh` 目录时**每个 shell 报错，且因为没有密钥，每个 shell 都会新起一个 `ssh-agent`。
- `converge/` 的组件会用 `sudo -n` 并装每小时的定时任务（由 git hook 和 cron 触发）。
- `gitrc/.gitconfig` 设了全局 `core.hooksPath`，提交后会自动 pull / push。
- 个别脚本写死主机名并会 ssh 到其它机器（如 `clauderc/auto_compact_guard.py`）。

## `~/.claude`、`~/.codex` 与 loadrc 的关系

- 两者是独立仓库（`claude-config`、`codex-config`）。`settings.json` 的 hooks / statusline 和 `hooks.json` 全部引用 `~/loadrc/clauderc/...`——**loadrc 必须放在 `~/loadrc`**。
- 两个仓库各有一个 git filter（`settings.json` 用 `claude-settings`，`config.toml` 用 `codex-runtime`），filter 命令写在各自的 `.git/config` 里，不随 clone 过来；安装脚本是 `clauderc/install_claude_filter.sh`、`clauderc/install_codex_filter.sh`，clone 之后要跑一次。
- 参考机 `~/.codex/config.toml` 里一部分内容由不在仓库里的 sidecar 文件（`config.local-keys.json`、`config.local-sections.toml`）生成，新机上不会有。
- 全局规则（`~/.claude/CLAUDE.md` 与 `~/.codex/AGENTS.md`）和技巧（17 个与 7 个）是**分开维护的两份**，没有同步脚本。
- `claude`、`codex` 命令是 `.shellrc` 里定义的 shell 函数，分别调 `clauderc/claude_wrapper.py`、`clauderc/codex_wrapper.py`。Claude 本体的位置写死为 `~/.local/bin/claude`（原生安装器的落点）；Codex 在 PATH、nvm、Homebrew 等几处找，参考机是 nvm 下 npm 装的 `@openai/codex`。
- `settings.json` 里引用了目标机上不存在的目录，并启用了需要额外二进制的 LSP 插件，影响未确认。
