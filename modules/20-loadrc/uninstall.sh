#!/bin/bash
# loadrc 的清理里「清单管不到」的部分：定时任务、还在跑的进程、iTerm2 的设置和守护进程、gh 的登录。
# 文件、目录和软链接（~/loadrc、~/.zshrc、~/.tmux.conf、~/.config/nvim 等）已记在清单里，
# 由 uninstall.sh 统一删除 / 放回。
# 每一步都先看清单：不是本次安装记下的，一律不碰（演练机上几个分支各用各的清单）。
set -uo pipefail
. "$MS_SRC/lib/common.sh"

CRON_BEGIN="# >>> cc-cron: CC 定时任务(install_cc_cron.sh 管理, 勿手改此块) >>>"
CRON_END="# <<< cc-cron <<<"
ITERM_DOMAIN="com.googlecode.iterm2"
ITERM_PLIST="$HOME/Library/LaunchAgents/com.huangyingw.iterm2-bell-daemon.plist"

# 清单里某一条的附加信息
ms_extra() {
    awk -F'\t' -v t="$1" -v v="$2" '$1==t && $2==v {print $3}' "$MS_MANIFEST" | head -1
}

# 在参考机上用假的 HOME 试跑（安装时带了 MS_LOADRC_SANDBOX=1）：下面几样都不在 $HOME 里，
# 安装时没碰，这里也不能碰——尤其钥匙串，删的会是参考机自己的登录。
[ -z "${MS_LOADRC_SANDBOX:-}" ] || exit 0

# 1. 定时任务：只摘掉我们加的那一块，对方的条目（含这段时间新加的）原样留下。
#    放在最前面：否则每分钟一次的巡查会在目录被删的同时还在跑。
if ms_recorded crontab user; then
    existing="$(crontab -l 2>/dev/null || true)"
    stripped="$(printf '%s\n' "$existing" | awk -v b="$CRON_BEGIN" -v e="$CRON_END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip')"
    if [ "$stripped" != "$existing" ]; then
        if [ -n "$(printf '%s' "$stripped" | tr -d '[:space:]')" ]; then
            printf '%s\n' "$stripped" | crontab -
        else
            crontab -r 2>/dev/null
        fi
        ms_log "已摘掉定时任务"
    fi
fi

# 2. iTerm2：停掉守护进程，把设置恢复成安装前的样子
if ms_recorded path "$ITERM_PLIST"; then
    launchctl unload "$ITERM_PLIST" 2>/dev/null
fi
case "$(ms_extra defaults "$ITERM_DOMAIN")" in
    saved)
        if [ -f "$MS_BACKUP_DIR/$ITERM_DOMAIN.plist" ]; then
            defaults delete "$ITERM_DOMAIN" 2>/dev/null
            if defaults import "$ITERM_DOMAIN" "$MS_BACKUP_DIR/$ITERM_DOMAIN.plist"; then
                ms_log "已放回原有的 iTerm2 设置"
            else
                ms_warn "原有的 iTerm2 设置没能放回，留在 $MS_BACKUP_DIR/$ITERM_DOMAIN.plist"
                touch "$MS_HOME/.keep"
            fi
        fi
        ;;
    none)
        defaults delete "$ITERM_DOMAIN" 2>/dev/null
        ;;
esac

# 3. 还在跑的东西：tmux 是我们装的 → 里面的会话都是我们开的，整个停掉；
#    再停掉从 ~/loadrc 起来的脚本（巡查、守护进程、agent 的包装脚本），否则它们会把文件重新写出来。
#    卸载自己所在的那条进程链不能停（在 tmux 里、或由 agent 代跑卸载时，停了卸载就断在半路）。
if ms_recorded path "$HOME/loadrc"; then
    if ms_recorded formula tmux && command -v tmux >/dev/null 2>&1; then
        if [ -n "${TMUX:-}" ]; then
            ms_warn "卸载是在 tmux 里跑的，没有停 tmux：跑完后请关掉这个终端窗口"
        else
            tmux kill-server 2>/dev/null
            # tmux 放 socket 的目录（tmux 是我们装的 → 这个目录也是我们用出来的）
            rm -rf "/private/tmp/tmux-$(id -u)"
        fi
    fi
    ancestors=" "
    p=$$
    while [ "${p:-0}" -gt 1 ]; do
        ancestors="$ancestors$p "
        p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
    done
    for pid in $(pgrep -f "$HOME/loadrc/" 2>/dev/null); do
        case "$ancestors" in *" $pid "*) continue ;; esac
        kill "$pid" 2>/dev/null
    done
fi

# 4. 巡查、hook、守护进程写在 /tmp 下的日志和状态：清单只管家目录等位置，这里按名字清。
#    只删属于当前用户的；名字都是这套工具专用的前缀，不会撞上别的程序。
if ms_recorded path "$HOME/loadrc"; then
    find /private/tmp -maxdepth 1 -user "$(id -un)" \( \
        -name 'login-watchdog*' -o -name 'model-watchdog*' -o -name 'safeguard-watchdog*' \
        -o -name 'rc-watchdog*' -o -name 'handoff-watchdog.log' -o -name 'handoff-sw-*' \
        -o -name 'agent_orphan_watchdog.log' -o -name 'agent_reopen_*' -o -name 'worktree-gc.log' \
        -o -name 'notify-attention.log' -o -name 'model-autoswitch*' -o -name '.model_switch_lease_*' \
        -o -name '.claude_model_*' -o -name 'switch-model-locks' -o -name 'project_desk_seen*' \
        -o -name 'resume-detector-mismatch.seen' -o -name 'iterm2-bell-daemon*' \
        \) -exec rm -rf {} + 2>/dev/null
fi

# 5. gh 的登录：安装时对方没有在用 gh → 钥匙串里现在有的是我登录留下的，删掉
if [ "$(ms_extra keychain "gh:github.com")" = ours ]; then
    n=0
    while [ "$n" -lt 10 ] && security delete-generic-password -s "gh:github.com" >/dev/null 2>&1; do
        n=$((n + 1))
    done
    [ "$n" -eq 0 ] || ms_log "已清掉钥匙串里 gh 的登录"
fi
exit 0
