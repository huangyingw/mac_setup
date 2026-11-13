#!/bin/bash
# loadrc：取快照到 ~/loadrc，接好 zsh / tmux / nvim / git / iTerm2 的配置，让 clauderc 的 multi-agent 工具能用。
#
# ~/loadrc 的来源是公开窗口期的 huangyingw/loadrc-snapshot（原仓库永不公开，见 AGENTS.md 第 5 节），
# 里面有什么由 snapshots/loadrc.include 决定。设计依据、与参考机的差异见 docs/decisions/loadrc-module.md。
#
# 调试用的环境变量：
#   MS_LOADRC_URL       换一个快照地址（如参考机上 SNAPSHOT_LOCAL_ONLY=1 导出的本地目录）
#   MS_LOADRC_SANDBOX=1 只做落在 $HOME 里的事，跳过 crontab / 应用设置 / launchd / 装软件
#                       （在参考机上用假的 HOME 试跑时用，免得动到参考机自己的环境）
set -euo pipefail
. "$MS_SRC/lib/common.sh"

SNAPSHOT_URL="${MS_LOADRC_URL:-https://github.com/huangyingw/loadrc-snapshot.git}"
SANDBOX="${MS_LOADRC_SANDBOX:-}"
LOADRC="$HOME/loadrc"
MOD_DIR="$MS_SRC/modules/20-loadrc"
TMP_DIR="$MS_HOME/tmp-loadrc"

# 和 cc.cron / install_cc_cron.sh 用同一对标记，装进去的块它们认得
CRON_BEGIN="# >>> cc-cron: CC 定时任务(install_cc_cron.sh 管理, 勿手改此块) >>>"
CRON_END="# <<< cc-cron <<<"
# 不装的定时任务：给参考机那几台机器用的（自动升级 npm 装的 Codex、跨机汇总后改配置），这里用不上
CRON_SKIP='codex_update\.py|auto_compact_guard\.py'

ITERM_DOMAIN="com.googlecode.iterm2"
ITERM_PLIST="$HOME/Library/LaunchAgents/com.huangyingw.iterm2-bell-daemon.plist"

# 匿名拉取：不弹账号输入、不用对方存的凭证、不触发全局 git 钩子（装好以后全局钩子会自动 pull / push）
ms_git() {
    GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c core.hooksPath=/dev/null "$@" </dev/null
}

# claim_new_dir <目录>...：目录原来没有 → 建出来并记为我们的；原来就有 → 不动、不记账
claim_new_dir() {
    local d
    for d in "$@"; do
        [ -e "$d" ] && continue
        ms_record path "$d"
        mkdir -p "$d"
    done
}

# own_if_absent <路径>...：路径原来没有 → 记为我们的（不创建）；原来就有 → 不动、不记账。
# 用在「我的工具运行时会往里写、但对方可能本来就有」的位置上。
own_if_absent() {
    local p
    for p in "$@"; do
        [ -e "$p" ] || [ -L "$p" ] || ms_record path "$p"
    done
}

# link <源> <落点>：落点上对方原有的东西先备份，再建软链接
link() {
    local src="$1" dst="$2"
    if [ ! -e "$src" ]; then
        ms_warn "快照里没有 ${src}，没有建 ${dst}"
        return 0
    fi
    ms_claim "$dst"
    # 对方原有的已经挪走；还在的只可能是我们上次建的
    if [ -d "$dst" ] && [ ! -L "$dst" ]; then ms_remove_path "$dst"; fi
    ln -sfn "$src" "$dst"
}

# ---------- 1. 依赖 ----------

if [ -z "$SANDBOX" ]; then
    ms_brew_ensure
    ms_formula git </dev/null
    # tmux：agent 会话都跑在 tmux 里。python：系统自带的 python3 只是占位程序，clauderc 的脚本要真的
    ms_formula tmux </dev/null || ms_die "tmux 安装失败"
    ms_formula python </dev/null || ms_die "python 安装失败"
    # gh：全局 git 配置把 GitHub 的凭证交给它。git-lfs：全局 git 配置把它设成了必需
    ms_formula gh </dev/null || ms_warn "gh 没装上：推送到 GitHub 时没有凭证来源"
    ms_formula git-lfs </dev/null || ms_warn "git-lfs 没装上：检出带 LFS 文件的仓库会报错"
else
    ms_brew_load || true
fi

# ---------- 2. ~/loadrc ----------
# 先拉到临时目录，成功了才动对方原有的东西。

if ms_recorded path "$LOADRC" && [ -d "$LOADRC/.git" ]; then
    # 重跑：只快进。拉不动不算失败（快照仓库可能已改回私有）
    if ms_git -C "$LOADRC" pull --ff-only --quiet; then
        ms_git -C "$LOADRC" submodule update --init --recursive --quiet \
            || ms_warn "~/loadrc 的子模块没能更新，沿用现有内容"
    else
        ms_warn "~/loadrc 没能更新到最新（快照仓库已改回私有？），沿用现有内容"
    fi
else
    ms_log "拉取 loadrc 快照 → ${LOADRC}"
    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"
    ms_git clone --quiet --recurse-submodules --shallow-submodules "$SNAPSHOT_URL" "$TMP_DIR/loadrc" \
        || ms_die "拉不到 ${SNAPSHOT_URL}（还没公开？参考机上先跑 local/publish.sh huangyingw/loadrc-snapshot）"
    ms_claim "$LOADRC"
    # 走到这里落点上还有东西，只可能是上次没装完留下的半成品（已记为我们的），清掉
    ms_remove_path "$LOADRC"
    mv "$TMP_DIR/loadrc" "$LOADRC"
    rm -rf "$TMP_DIR"
fi

# ---------- 3. 配置落位 ----------

claim_new_dir "$HOME/.config" "$HOME/.local" "$HOME/.local/share" "$HOME/.local/state" "$HOME/.cache"

# zsh：~/.zshrc 用本模块自带的版本（与参考机的差异写在那个文件开头）
link "$LOADRC/oh-my-zsh" "$HOME/.oh-my-zsh"
ms_claim "$HOME/.zshrc"
cp "$MOD_DIR/zshrc" "$HOME/.zshrc"
ms_claim "$HOME/.zsh_history_mac_setup"

# tmux
link "$LOADRC/.tmux" "$HOME/.tmux"
link "$LOADRC/.tmux.conf" "$HOME/.tmux.conf"
ms_claim "$HOME/.local/share/tmux"

# vim / nvim。nvim 自己的数据、状态、缓存目录也先让出来，免得我的插件和对方原有的混在一起
link "$LOADRC/vimrc/.vim" "$HOME/.vim"
link "$LOADRC/vimrc/.vimrc" "$HOME/.vimrc"
ms_claim "$HOME/.config/nvim"
mkdir -p "$HOME/.config/nvim"
ln -sfn "$LOADRC/neovim/init.lua" "$HOME/.config/nvim/init.lua"
ln -sfn "$LOADRC/neovim/.config/nvim/lua" "$HOME/.config/nvim/lua"
ms_claim "$HOME/.local/share/nvim"
ms_claim "$HOME/.local/state/nvim"
ms_claim "$HOME/.cache/nvim"
ms_claim "$HOME/.viminfo"

# git：全局配置、全局忽略清单、全局钩子（与参考机一样：提交后自动 pull / push 到已配置的上游）
link "$LOADRC/gitrc/.gitconfig" "$HOME/.gitconfig"
link "$LOADRC/gitrc/.globalgitignore" "$HOME/.globalgitignore"
link "$LOADRC/.git-templates" "$HOME/.git-templates"

# nvim 的插件清单里有 4 个地址写的是 Bitbucket 的 ssh 地址，这台机器没有密钥、拉不到。
# 它们在 GitHub 上都有公开的同一份（两个是我自己的仓库，两个我没改过、用原作者的），
# 这里只对这 4 个地址做改写，不动别的 git@ 地址（对方自己的仓库可能正用着 ssh 密钥）。
claim_new_dir "$HOME/.config/git"
ms_claim "$HOME/.config/git/config"
cat > "$HOME/.config/git/config" <<'EOF'
# 由 mac_setup 的 20-loadrc 模块生成。
[url "https://github.com/huangyingw/bash-support.vim.git"]
    insteadOf = git@bitbucket.org:huangyingw/bash-support.vim.git
[url "https://github.com/huangyingw/split-term.vim.git"]
    insteadOf = git@bitbucket.org:huangyingw/split-term.vim.git
[url "https://github.com/jelera/vim-javascript-syntax.git"]
    insteadOf = git@bitbucket.org:huangyingw/vim-javascript-syntax.git
[url "https://github.com/dzeban/vim-log-syntax.git"]
    insteadOf = git@bitbucket.org:huangyingw/vim-log-syntax.git
EOF

# gh：我登录后的账号记在这里和钥匙串里。对方原来就用着 gh → 不动，也不记账
if [ ! -e "$HOME/.config/gh" ]; then
    ms_record path "$HOME/.config/gh"
    ms_record keychain "gh:github.com" ours
fi

# multi-agent 工具运行时会在家目录里写的东西，先记上（对方原有的会先备份）
ms_claim "$HOME/.cache/loadrc"
ms_claim "$HOME/.cache/agent-tower"
ms_claim "$HOME/.agent_projects.list"
ms_claim "$HOME/.agent-lang.json"
# 定时巡查和 hook 脚本会往 Claude Code / Codex 的配置目录里写日志和缓存。对方原来没有这两个目录 →
# 先记为我们的：30-agents 还没装、或巡查抢在它前面把目录建了出来，卸载时都能删干净，
# 也不会被 30-agents 当成「对方原有的」备份起来再放回去。
own_if_absent "$HOME/.claude" "$HOME/.codex" "$HOME/.config/loadrc"
# 系统自带的 python3 跑我的脚本时留下的字节码缓存
own_if_absent "$HOME/Library/Caches/com.apple.python"

# ---------- 4. nvim 插件 ----------
# 配置里的插件平时是第一次打开 nvim 时在后台装、重启后才生效；这里先装好，打开就能用。

if command -v nvim >/dev/null 2>&1; then
    ms_log "预装 nvim 插件（要几分钟）"
    if GIT_TERMINAL_PROMPT=0 nvim --headless "+Lazy! install" +qa </dev/null >"$MS_HOME/nvim-plugins.log" 2>&1; then
        n="$(find "$LOADRC/neovim/lazy" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
        ms_log "nvim 插件已装 ${n} 个"
    else
        ms_warn "nvim 插件没有全部装上（记录在 ${MS_HOME}/nvim-plugins.log），打开 nvim 时会在后台补装"
    fi
else
    ms_warn "没有 nvim（由 10-base 模块装）：插件留到第一次打开 nvim 时在后台装"
fi

# ---------- 5. 定时任务 ----------
# cc.cron 里的巡查脚本：交接卡住时自动重发、会话卡在登录或选择框时提醒 / 处理、清理孤儿进程等。
# 只往 crontab 里加带标记的一块，对方原有的条目原样保留；卸载时只摘掉这一块。

cron_install() {
    local src="$LOADRC/clauderc/cc.cron" entries existing stripped n
    [ -f "$src" ] || { ms_warn "快照里没有 clauderc/cc.cron，没有装定时任务"; return 0; }
    entries="$(grep -vE '^[[:space:]]*(#|$)' "$src" | grep -vE "$CRON_SKIP" || true)"
    [ -n "$entries" ] || return 0
    existing="$(crontab -l 2>/dev/null || true)"
    if ! ms_recorded crontab user; then
        # 留一份原样的，万一要手工核对
        printf '%s\n' "$existing" > "$MS_BACKUP_DIR/crontab.orig"
        if [ -n "$existing" ]; then ms_record crontab user had; else ms_record crontab user none; fi
    fi
    stripped="$(printf '%s\n' "$existing" | awk -v b="$CRON_BEGIN" -v e="$CRON_END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip')"
    if [ -n "$stripped" ]; then
        printf '%s\n%s\n%s\n%s\n' "$stripped" "$CRON_BEGIN" "$entries" "$CRON_END" | crontab -
    else
        printf '%s\n%s\n%s\n' "$CRON_BEGIN" "$entries" "$CRON_END" | crontab -
    fi
    n="$(printf '%s\n' "$entries" | grep -c .)"
    if crontab -l 2>/dev/null | grep -qF "$CRON_BEGIN"; then
        ms_log "已装定时任务 ${n} 条"
    else
        ms_warn "定时任务没有写进 crontab（系统拦了？）：交接卡住时不会自动重发"
        ms_todo "定时任务没装上：在终端运行 bash ~/loadrc/clauderc/install_cc_cron.sh，系统弹出授权时点允许"
    fi
}
if [ -z "$SANDBOX" ]; then cron_install; fi

# ---------- 6. iTerm2 ----------
# 标签染色守护进程（会话要人处理时把标签染色、响铃）和它依赖的几项设置，用 loadrc 自带的安装脚本。
# 对方原来就有 iTerm2 的设置 → 先存一份，卸载时放回。

iterm_setup() {
    [ -d /Applications/iTerm.app ] || { ms_warn "没有 iTerm2（由 10-base 模块装），跳过它的配置"; return 0; }
    [ -f "$LOADRC/iterm2rc/install.sh" ] || { ms_warn "快照里没有 iterm2rc，跳过 iTerm2 的配置"; return 0; }
    if ! ms_recorded defaults "$ITERM_DOMAIN"; then
        if defaults read "$ITERM_DOMAIN" >/dev/null 2>&1; then
            defaults export "$ITERM_DOMAIN" "$MS_BACKUP_DIR/$ITERM_DOMAIN.plist"
            ms_record defaults "$ITERM_DOMAIN" saved
        else
            ms_record defaults "$ITERM_DOMAIN" none
        fi
    fi
    ms_claim "$HOME/.local/iterm2-venv"
    claim_new_dir "$HOME/Library/LaunchAgents"
    ms_claim "$ITERM_PLIST"
    claim_new_dir "$HOME/Library/Application Support/iTerm2" \
                  "$HOME/Library/Application Support/iTerm2/Scripts" \
                  "$HOME/Library/Application Support/iTerm2/Scripts/AutoLaunch"
    ms_claim "$HOME/Library/Application Support/iTerm2/Scripts/AutoLaunch/restart-bell-daemon.py"
    if bash "$LOADRC/iterm2rc/install.sh" </dev/null >"$MS_HOME/iterm2-setup.log" 2>&1; then
        ms_log "iTerm2 已配置"
    else
        ms_warn "iTerm2 的配置没有全部完成（记录在 ${MS_HOME}/iterm2-setup.log），不影响其余功能"
    fi
    ms_todo "iTerm2：已经开着的话退出重开一次；弹出「python 想要控制 iTerm」时点允许（标签染色要用）"
}
if [ -z "$SANDBOX" ]; then iterm_setup; fi

# ---------- 7. 收尾 ----------

ms_log "~/loadrc 在快照提交 $(ms_git -C "$LOADRC" rev-parse --short HEAD)（$(sed -n 's/^来源提交: //p' "$LOADRC/SNAPSHOT_SOURCE" 2>/dev/null | cut -c1-9)）"

if [ -z "$SANDBOX" ]; then
    shell_now="$(dscl . -read "$HOME" UserShell 2>/dev/null | awk '{print $2}')"
    case "$shell_now" in
        */zsh) ;;
        *) ms_todo "这台机器的默认 shell 是 ${shell_now:-未知}（不是 zsh）：开终端后先运行 zsh，才是我的环境" ;;
    esac
fi
ms_todo "新开一个终端窗口，才会用上新的 shell 配置"
ms_todo "GitHub：要推送代码时先运行 gh auth login 登录你的账号（全局 git 钩子会在提交后自动 pull / push 到已配置的上游）"
