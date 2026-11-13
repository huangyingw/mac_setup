#!/bin/bash
# 语音输入的清理里「清单管不到」的部分：停掉转写服务和 Spokenly、收回系统授权、清掉钥匙串里的记录。
# 文件和目录（应用设置、听写历史、转写服务目录、launchd 配置）已记在清单里，由 uninstall.sh 统一删除 / 放回；
# Spokenly 本体和 uv 由 uninstall.sh 按清单卸载；共用的上级目录（newdir）也由它统一处理。
set -uo pipefail
. "$MS_SRC/lib/common.sh"

LABEL="com.huangyingw.qwen3-asr"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
KEYCHAIN_SVC="app.spokenly.FSDService"
PREFS="$HOME/Library/Preferences/app.spokenly.plist"

# 清单里没有本模块的记录 → 什么都不做。
# （恢复原状会依次跑每个模块的清理；用别的状态目录、或者没装过本模块时，不能去动对方正开着的 Spokenly）
if ! ms_recorded path "$PREFS" && ! ms_recorded path "$AGENT" \
        && ! ms_recorded cask spokenly && ! ms_recorded keychain "$KEYCHAIN_SVC"; then
    exit 0
fi

# 1. 停掉转写服务（launchd 配置是我们放的才停），等它退干净，免得目录被删之后又被写出来
if ms_recorded path "$AGENT"; then
    uid="$(id -u)"
    launchctl bootout "gui/$uid/$LABEL" 2>/dev/null
    i=0
    while launchctl print "gui/$uid/$LABEL" >/dev/null 2>&1 && [ "$i" -lt 30 ]; do sleep 1; i=$((i + 1)); done
fi

# 2. 退出 Spokenly：它开着的话会把内存里的设置写回去，盖掉放回去的原有设置
if ms_recorded path "$PREFS" && pgrep -x Spokenly >/dev/null 2>&1; then
    pkill -x Spokenly 2>/dev/null
    i=0
    while pgrep -x Spokenly >/dev/null 2>&1 && [ "$i" -lt 15 ]; do sleep 1; i=$((i + 1)); done
    pgrep -x Spokenly >/dev/null 2>&1 && ms_warn "Spokenly 没有退出，它的设置可能没有恢复干净"
fi

# 3. Spokenly 是我们装的 → 收回给它的系统授权（麦克风、辅助功能等）。对方原来就有的不碰。
if ms_recorded cask spokenly; then
    tccutil reset All app.spokenly >/dev/null 2>&1 && ms_log "已收回给 Spokenly 的系统授权"
fi

# 4. 钥匙串里 Spokenly 自己写的记录：安装时确认过原来没有的才删
if ms_recorded keychain "$KEYCHAIN_SVC"; then
    n=0
    while [ "$n" -lt 10 ] && security delete-generic-password -s "$KEYCHAIN_SVC" >/dev/null 2>&1; do
        n=$((n + 1))
    done
    [ "$n" -eq 0 ] || ms_log "已清掉钥匙串里 Spokenly 的记录"
fi

# 5. Homebrew 下载缓存里我们装的那两样的安装包。
#    Homebrew 是我们装的会整个卸掉、连缓存一起没；它原来就有时卸载软件不清缓存，这里补上。
ms_brew_load 2>/dev/null || true
cache="$(brew --cache 2>/dev/null || true)"
# drop_cached <缓存里的链接>...：删掉链接和它指向的安装包
drop_cached() {
    local f t
    for f in "$@"; do
        [ -L "$f" ] || continue
        t="$(readlink "$f")"
        case "$t" in /*) ;; *) t="$(dirname "$f")/$t" ;; esac
        rm -f "$t" "$f"
    done
}
if [ -n "$cache" ] && [ -d "$cache" ]; then
    if ms_recorded cask spokenly; then drop_cached "$cache"/Cask/spokenly--*; fi
    if ms_recorded formula uv; then drop_cached "$cache"/uv--* "$cache"/uv_bottle_manifest--*; fi
fi

# 6. 让系统的设置缓存重新读盘：接下来设置文件会被直接删掉 / 放回
if ms_recorded path "$PREFS"; then killall -u "$(id -un)" cfprefsd 2>/dev/null; fi
exit 0
