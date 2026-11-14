#!/bin/bash
# 远程图形连接：NoMachine。装好后从别的机器用 NoMachine 客户端连这台机器（NX 协议，端口 4000），
# 用这台机器的账号和登录密码登录，看到的是它的实际桌面。
#
# 参考机现状（2026-11-13 调查，细节见 docs/decisions/nomachine.md）：
#   - Homebrew cask `nomachine`（官方 pkg，自带自动更新）；
#   - 服务端配置 server.cfg / node.cfg 与安装包自带的完全相同（同目录的 .backup 是安装时的原样，
#     没有差异），所以这里不改任何配置，装好就是参考机的状态；
#   - 系统授权：「屏幕与系统录音」和「辅助功能」都给了 NoMachine（com.nomachine.nxdock）。
#     脚本给不了，登记为人工事项——不授权的话连上去只看得到桌面背景、鼠标键盘也不起作用。
#
# 安装包会改动的系统位置（恢复原状时由 uninstall.sh 调官方卸载脚本清掉）：
#   /Applications/NoMachine.app、/Library/Application Support/NoMachine、/Library/LaunchDaemons 与
#   /Library/LaunchAgents 下的 com.nomachine.*、/etc/NX、/etc/pam.d/nx、/Library/Audio/Plug-Ins/HAL 下的
#   NMAudio*.driver、隐藏的系统用户 nx（和组 nx）。
set -euo pipefail
. "$MS_SRC/lib/common.sh"

APP="/Applications/NoMachine.app"
NXD="$APP/Contents/Frameworks/bin/nxd"
PORT=4000
FW=/usr/libexec/ApplicationFirewall/socketfilterfw

# 对方原来就装着 NoMachine：不动它，也不碰它的配置和用户数据
if [ -d "$APP" ] && ! ms_recorded cask nomachine; then
    ms_log "NoMachine 原来就有，不动（配置也不改）"
    ms_todo "NoMachine：这台机器原来就装着，没有改它的设置；能不能从别的机器连进来取决于机主原来的配置"
    exit 0
fi

# NoMachine 运行时会往当前用户家目录写的位置。装之前认领：原有的先挪进备份，
# 我们用过留下的（连接记录、日志、录像和收到的文件）恢复原状时直接删掉，不进废纸篓。
# （cask 的 zap 也列了后两项，但它是挪进废纸篓，会留在对方机器上，所以这里自己管。）
for p in \
    "$HOME/.nx" \
    "$HOME/Documents/NoMachine" \
    "$HOME/Library/Preferences/com.nomachine.nxdock.plist" \
    "$HOME/Library/Saved Application State/com.nomachine.nxdock.savedState"; do
    ms_claim "$p"
done

# 应用目录已经不在、但系统里还留着上次装 NoMachine 的残余（对方卸得不干净）：照装，提醒一句。
# 恢复原状时官方卸载脚本会把这些一起清掉。
if [ -d /etc/NX ] || dscl . -read /Users/nx >/dev/null 2>&1; then
    if ! ms_recorded cask nomachine; then
        ms_warn "这台机器上有以前装过 NoMachine 的残余（/etc/NX 或系统用户 nx），恢复原状时会一并清掉"
    fi
fi

# 安装包会把它建的系统用户 nx 加进登录窗口的「隐藏用户列表」。这个列表原来没有 → 记账，
# 恢复原状时整项删掉，而不是留一个空列表。
if ! ms_recorded cask nomachine \
        && ! defaults read /Library/Preferences/com.apple.loginwindow HiddenUsersList >/dev/null 2>&1; then
    ms_record nm-hidden-list absent
fi

ms_cask nomachine NoMachine.app || ms_die "NoMachine 安装失败"

# 防火墙开着时，放行 NoMachine 的监听进程（nxd），并记账，恢复原状时撤掉。
# 「阻止所有传入连接」模式下放行也没用，只能由人决定要不要关。
fw_state="$("$FW" --getglobalstate 2>/dev/null || true)"
case "$fw_state" in
    *"State = 1"*)
        if ! "$FW" --listapps 2>/dev/null | grep -Fq "$NXD"; then
            sudo "$FW" --add "$NXD" >/dev/null
            ms_record fwapp "$NXD"
        fi
        sudo "$FW" --unblockapp "$NXD" >/dev/null
        ms_log "防火墙开着，已放行 NoMachine"
        ;;
    *"State = 2"*)
        ms_todo "NoMachine：这台机器的防火墙设成了「阻止所有传入连接」，别的机器连不进来；要连的话在 系统设置 → 网络 → 防火墙 → 选项 里关掉这一项（会影响这台机器的安全设置，先问机主）"
        ;;
esac

# 安装包装完会自己拉起服务。等它在 4000 端口上开始监听。
ms_log "等 NoMachine 服务就绪..."
i=0
until nc -z -G 2 127.0.0.1 "$PORT" >/dev/null 2>&1; do
    if [ "$i" -ge 60 ]; then
        sudo /etc/NX/nxserver --restart >/dev/null 2>&1 || true
    fi
    [ "$i" -lt 90 ] || ms_die "NoMachine 服务 3 分钟内没有在 ${PORT} 端口监听（看 sudo /etc/NX/nxserver --status）"
    sleep 2; i=$((i + 1))
done
ms_log "NoMachine 服务已在 ${PORT} 端口监听"

host="$(scutil --get LocalHostName 2>/dev/null || hostname -s).local"
ips="$(ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {printf "%s ", $2}')"
ms_todo "NoMachine：系统设置 → 隐私与安全性 → 「屏幕与系统录音」和「辅助功能」，都打开 NoMachine 的开关（不开的话连上去只看得到桌面背景，鼠标键盘也不起作用）；这一步要在这台机器跟前做"
ms_todo "NoMachine：在别的机器上打开 NoMachine 客户端，连 ${host}（端口 ${PORT}；连不上就用 IP），用这台机器的账号 $(id -un) 和它的登录密码登录"

ms_log "NoMachine 已装好：从别的机器连 ${host} 或 ${ips% }（端口 ${PORT}）"
