#!/bin/bash
# Claude Code 与 Codex 的清理里「清单管不到」的部分：停掉还在跑的进程、清掉钥匙串里的登录。
# 文件和目录（~/.claude、~/.codex、~/.claude.json、Claude Code 本体等）已记在清单里，由 uninstall.sh 统一删除 / 放回。
set -uo pipefail
. "$MS_SRC/lib/common.sh"

# 1. 停掉我们装的工具还在跑的进程，否则它们会在目录被删之后把文件重新写出来。
#    对方原来就有的那份（没记账）不碰。
if ms_recorded path "$HOME/.local/bin/claude"; then
    pkill -f "$HOME/.local/bin/claude" 2>/dev/null
    pkill -f "$HOME/.local/share/claude/versions/" 2>/dev/null
fi
if ms_recorded cask codex; then
    pkill -f "/Caskroom/codex/" 2>/dev/null
    pkill -x codex 2>/dev/null
fi

# 2. 钥匙串里的登录。安装时记过每个服务原来的状态：
#    ours  原来没有        → 现在有的都是我登录留下的，删掉
#    saved 原来有、已存一份 → 删掉我的，把原来的放回去
#    lost  原来有、没存下来 → 删掉我的（安装时已登记要告诉机主重新登录）
#    没记过                → 不碰
keychain_restore() {
    local svc="$1" state f="$MS_BACKUP_DIR/keychain/$1" n=0
    state="$(awk -F'\t' -v s="$svc" '$1=="keychain" && $2==s {print $3}' "$MS_MANIFEST" | head -1)"
    [ -n "$state" ] || return 0
    while [ "$n" -lt 10 ] && security delete-generic-password -s "$svc" >/dev/null 2>&1; do
        n=$((n + 1))
    done
    [ "$n" -eq 0 ] || ms_log "已清掉钥匙串里「${svc}」的登录"
    if [ "$state" = saved ] && [ -s "$f" ]; then
        if security add-generic-password -U -s "$svc" -a "$(cat "$f.acct" 2>/dev/null)" -w "$(cat "$f")" 2>/dev/null; then
            ms_log "已放回原有的「${svc}」登录"
        else
            ms_warn "原有的「${svc}」登录没能放回，机主需要重新登录"
        fi
    fi
    rm -f "$f" "$f.acct"
}

keychain_restore "Claude Code-credentials"
keychain_restore "Codex Auth"
exit 0
