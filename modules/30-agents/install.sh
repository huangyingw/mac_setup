#!/bin/bash
# Claude Code 与 Codex：装上，并把 ~/.claude、~/.codex 配成与参考机一样（全局规则、技巧、hooks）。
#
# 参考机现状（2026-11-13 调查）：
#   - Claude Code 用官方原生安装器装，落点 ~/.local/bin/claude（loadrc 的包装脚本写死了这个位置）；
#   - Codex 在参考机上是 npm 装的；这里改用 Homebrew 的同名 cask（同一个版本、不必先装 node、卸载有记账）；
#   - ~/.claude 就是 GitHub huangyingw/claude-config 的检出，~/.codex 就是 huangyingw/codex-config 的检出，
#     两个都在 integration 分支。hooks / 状态栏引用的脚本在 ~/loadrc/clauderc（由 20-loadrc 模块提供）。
#
# 不随仓库走、要人工做的：两个工具的账号登录。模型选择是各机自己的状态，也不在仓库里。
set -euo pipefail
. "$MS_SRC/lib/common.sh"

GH_BASE="https://github.com/huangyingw"
CONFIG_BRANCH="integration"
CLAUDE_BIN="$HOME/.local/bin/claude"
TMP_DIR="$MS_HOME/tmp"

# 登录态可能记在系统钥匙串里的服务名（Codex 默认记在 ~/.codex/auth.json，设成 keyring 时才用钥匙串）
KEYCHAIN_CLAUDE="Claude Code-credentials"
KEYCHAIN_CODEX="Codex Auth"

# 匿名拉取：不弹账号输入、不用对方存的 GitHub 凭证、不触发全局 git 钩子（loadrc 的全局钩子会自动 pull / push）
ms_git() {
    GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c core.hooksPath=/dev/null "$@" </dev/null
}

# claim_new_dir <目录>...：目录原来没有 → 建出来并记为我们的（卸载时整个删掉）；原来就有 → 不动、不记账
claim_new_dir() {
    local d
    for d in "$@"; do
        [ -e "$d" ] && continue
        ms_record path "$d"
        mkdir -p "$d"
    done
}

# config_repo <仓库名> <落点>：把配置仓库检出到落点。先拉到临时目录，成功了才动对方原有的东西。
config_repo() {
    local slug="$1" dest="$2" tmp="$TMP_DIR/$1"
    if ms_recorded path "$dest" && [ -d "$dest/.git" ]; then
        # 重跑：只快进到最新。拉不动不算失败（仓库可能已改回私有，或工具运行时改过被跟踪的文件）
        ms_git -C "$dest" pull --ff-only --quiet \
            || ms_warn "${dest} 没能更新到最新（仓库已改回私有？），沿用现有内容"
        return 0
    fi
    ms_log "拉取 ${slug} → ${dest}"
    mkdir -p "$TMP_DIR"
    rm -rf "$tmp"
    ms_git clone --quiet --branch "$CONFIG_BRANCH" "$GH_BASE/$slug.git" "$tmp" \
        || ms_die "拉不到 ${GH_BASE}/${slug}（还没公开？参考机上先跑 local/publish.sh huangyingw/${slug}）"
    ms_claim "$dest"
    # 走到这里落点上还有东西，只可能是上次没装完留下的半成品（已记为我们的），清掉
    ms_remove_path "$dest"
    mv "$tmp" "$dest"
}

# keychain_note <服务名>：第一次运行时记下钥匙串里这个服务原来有没有登录。
#   没有 → 记 ours：之后出现的都是我登录留下的，卸载时删掉。
#   有   → 存一份到备份目录，卸载时放回；存不下来就如实登记到人工事项里。
keychain_note() {
    local svc="$1" acct dir="$MS_BACKUP_DIR/keychain" f
    ms_recorded keychain "$svc" && return 0
    if ! security find-generic-password -s "$svc" >/dev/null 2>&1; then
        ms_record keychain "$svc" ours
        return 0
    fi
    f="$dir/$svc"
    mkdir -p "$dir"
    chmod 700 "$dir"
    acct="$(security find-generic-password -s "$svc" 2>/dev/null | sed -n 's/^ *"acct"<blob>="\(.*\)"$/\1/p' | head -1)"
    if (umask 077; security find-generic-password -s "$svc" -w > "$f" 2>/dev/null) && [ -s "$f" ]; then
        printf '%s\n' "$acct" > "$f.acct"
        ms_record keychain "$svc" saved
        ms_log "这台机器的钥匙串里原来就有「${svc}」的登录，已存一份，恢复原状时放回"
    else
        rm -f "$f"
        ms_record keychain "$svc" lost
        ms_todo "钥匙串里原来就有「${svc}」的登录，但没能备份：你登录后会覆盖它，恢复原状时会清掉，机主之后要自己重新登录——请提前告诉对方"
    fi
}

has_codex() {
    local p
    command -v codex >/dev/null 2>&1 && return 0
    for p in "$HOME/.npm-global/bin/codex" "$HOME/.local/bin/codex" /usr/local/bin/codex \
             "$HOME"/.nvm/versions/node/*/bin/codex; do
        [ -x "$p" ] && return 0
    done
    return 1
}

ms_brew_ensure
ms_formula git

# ---------- 1. 配置：~/.claude、~/.codex ----------
# 先于安装程序：安装器和工具首次启动都会往这两个目录写东西，目录必须已经是我们的检出。

keychain_note "$KEYCHAIN_CLAUDE"
keychain_note "$KEYCHAIN_CODEX"

config_repo claude-config "$HOME/.claude"
config_repo codex-config "$HOME/.codex"

# ~/.claude.json 是 Claude Code 放在家目录的状态文件（登录账号、项目记录、界面开关）。
# 对方原有的先挪走，免得我的账号和项目记录混进去；卸载时删掉我的、放回对方的。
# 它的伴生文件（.backup、写到一半的 .tmp.*）名字不固定：只在第一次运行时把对方原有的逐个挪走，
# 之后再出现的都是我的（重跑时不能再挪，否则会把我的当成对方的、卸载时放回去）。
if ! ms_recorded path "$HOME/.claude.json"; then
    for f in "$HOME"/.claude.json.*; do
        if [ -e "$f" ]; then ms_backup "$f"; fi
    done
fi
ms_claim "$HOME/.claude.json"
if [ ! -e "$HOME/.claude.json" ]; then
    # 参考机在这里关掉了「恢复会话时的摘要提示」。这个开关只在本文件里生效（见 settings.json 里的说明）。
    printf '{\n  "resumeReturnDismissed": true\n}\n' > "$HOME/.claude.json"
fi

# 两个仓库各有一个 git 过滤器（把工具自己写进配置文件的本机状态挡在 git 之外），命令记在各自的
# .git/config 里、不随检出过来。安装脚本在 loadrc 里，有就跑一次；没有不影响使用。
for f in install_claude_filter.sh install_codex_filter.sh; do
    if [ -x "$HOME/loadrc/clauderc/$f" ]; then
        "$HOME/loadrc/clauderc/$f" >/dev/null 2>&1 || ms_warn "${f} 没跑成功（不影响使用）"
    fi
done

# ---------- 2. Claude Code ----------

if [ -e "$CLAUDE_BIN" ] && ! ms_recorded path "$CLAUDE_BIN"; then
    ms_log "Claude Code 原来就有（${CLAUDE_BIN}），不动"
elif [ ! -x "$CLAUDE_BIN" ]; then
    ms_log "安装 Claude Code（官方安装器）"
    claim_new_dir "$HOME/.local" "$HOME/.local/bin" "$HOME/.local/share" "$HOME/.local/state" "$HOME/.cache"
    ms_claim "$CLAUDE_BIN"
    ms_claim "$HOME/.local/share/claude"
    ms_claim "$HOME/.local/state/claude"
    ms_claim "$HOME/.cache/claude"
    ms_claim "$HOME/Library/Caches/claude-cli-nodejs"
    mkdir -p "$TMP_DIR"
    curl -fsSL https://claude.ai/install.sh -o "$TMP_DIR/claude-install.sh" \
        || ms_die "下载 Claude Code 安装器失败"
    /bin/bash "$TMP_DIR/claude-install.sh" </dev/null || ms_die "Claude Code 安装器报错"
    [ -x "$CLAUDE_BIN" ] || ms_die "Claude Code 装完后找不到 ${CLAUDE_BIN}"
fi

# ---------- 3. Codex ----------

if ! ms_recorded cask codex && has_codex; then
    ms_log "Codex 原来就有，不动"
else
    # brew 会读标准输入；堵上，免得它吃掉调用方经标准输入送进来的后续命令
    ms_cask codex </dev/null || ms_die "Codex 安装失败"
fi

# 两个工具接 Chrome 扩展时，会各往 Chrome 的目录里写一份「本机消息」清单；Codex 还会在 ~/.cache 下放运行时。
# 这些都在配置目录之外，先记上（对方原有的会先备份）。
NMH_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
ms_claim "$NMH_DIR/com.anthropic.claude_code_browser_extension.json"
ms_claim "$NMH_DIR/com.openai.codexextension.json"
ms_claim "$HOME/.cache/codex-runtimes"

# ---------- 4. Claude Code 插件 ----------
# settings.json 的 enabledPlugins 里标为 true 的插件要另外下载才生效（下载下来的东西不在配置仓库里）。
# 参考机启用的都来自官方插件市场；别的市场这里不认识，如实提示。

plugins_setup() {
    local settings="$HOME/.claude/settings.json" want id installed keep="$TMP_DIR/settings.json.keep"
    [ -f "$settings" ] || return 0
    want="$(sed -n '/"enabledPlugins"/,/}/p' "$settings" | sed -n 's/^ *"\([^"]*\)": *true.*/\1/p')"
    [ -n "$want" ] || return 0
    installed="$("$CLAUDE_BIN" plugin list 2>/dev/null </dev/null || true)"
    # 「添加市场」会往 settings.json 里加一段参考机没有的内容；装完把文件原样放回去（市场另有地方记着，不受影响）
    mkdir -p "$TMP_DIR"
    cp "$settings" "$keep"
    for id in $want; do
        case "$installed" in *"$id"*) continue ;; esac
        case "$id" in
            *@claude-plugins-official)
                "$CLAUDE_BIN" plugin marketplace list 2>/dev/null </dev/null | grep -q claude-plugins-official \
                    || "$CLAUDE_BIN" plugin marketplace add anthropics/claude-plugins-official >/dev/null 2>&1 </dev/null \
                    || true
                if "$CLAUDE_BIN" plugin install "$id" >/dev/null 2>&1 </dev/null; then
                    ms_log "已装 Claude Code 插件 ${id}"
                else
                    ms_warn "Claude Code 插件 ${id} 没装上（不影响其余功能，登录后可在 claude 里用 /plugin 补装）"
                fi
                ;;
            *) ms_warn "Claude Code 插件 ${id} 来自这里不认识的插件市场，没有装" ;;
        esac
    done
    cp "$keep" "$settings"
}
if [ -x "$CLAUDE_BIN" ]; then plugins_setup; fi

rm -rf "$TMP_DIR"

# ---------- 5. 收尾 ----------

ms_log "Claude Code: $("$CLAUDE_BIN" --version 2>/dev/null || echo 运行不了)"
ms_log "Codex: $(codex --version 2>/dev/null || echo 运行不了)"
ms_log "~/.claude 在提交 $(ms_git -C "$HOME/.claude" rev-parse --short HEAD)，~/.codex 在提交 $(ms_git -C "$HOME/.codex" rev-parse --short HEAD)"

if [ ! -d "$HOME/loadrc/clauderc" ]; then
    ms_warn "没有 ~/loadrc/clauderc：Claude Code / Codex 的 hooks、状态栏和 claude / codex 启动命令都靠它（20-loadrc 模块）"
fi

ms_todo "Claude Code：在终端运行 claude，按提示登录你的 Anthropic 账号"
ms_todo "Codex：在终端运行 codex，按提示登录你的 ChatGPT 账号"
