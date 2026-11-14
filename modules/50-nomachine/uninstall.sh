#!/bin/bash
# NoMachine 的清理里「清单管不到」的部分：系统级的服务、驱动、系统用户、防火墙放行、系统授权。
# 家目录里的文件（~/.nx、~/Documents/NoMachine、设置文件）已记在清单里，由 uninstall.sh 统一删除 / 放回。
# NoMachine 不经 Homebrew 装（清单里记 nm-pkg），框架不会替我们卸，全在这里做。
#
# NoMachine 的官方卸载是「应用被删 → 守护进程 com.nomachine.uninstall 发现后跑 nxuninstall.sh」，新系统上
# 删系统用户那一步还交给一个要输密码的「NoMachine Uninstall」窗口（没人点就一直挂着）。
# 这里照官方流程同步跑一遍官方脚本，再自己补上交给图形界面的那部分。
set -uo pipefail
. "$MS_SRC/lib/common.sh"

APP="/Applications/NoMachine.app"
SUPPORT="/Library/Application Support/NoMachine"
VENDOR="$SUPPORT/nxuninstall.sh"
AGENT_PLIST="/Library/LaunchAgents/com.nomachine.uninstallAgent.plist"
FW=/usr/libexec/ApplicationFirewall/socketfilterfw

# 1. 防火墙里我们加的放行条目（清单里有才动）
awk -F'\t' '$1=="fwapp"{print $2}' "$MS_MANIFEST" 2>/dev/null | while IFS= read -r p; do
    [ -n "$p" ] || continue
    sudo "$FW" --remove "$p" >/dev/null 2>&1 && ms_log "已撤掉防火墙对 $p 的放行"
done

# 安装中途被打断时留下的挂载
hdiutil detach -quiet "$MS_HOME/nomachine-mnt" 2>/dev/null

# NoMachine 不是我们装的（或用别的状态目录、没装过本模块）→ 系统级的东西一概不碰
ms_recorded nm-pkg "$APP" || ms_recorded cask nomachine || exit 0

uid="$(id -u)"

# 2. 先停掉两个会抢着动手的官方卸载触发器：
#    - com.nomachine.uninstall 监视应用目录，下一步删应用时会在后台另跑一份官方脚本，和这里撞车；
#    - com.nomachine.uninstallAgent 会被官方脚本拉起，弹出要输密码的卸载窗口。
sudo launchctl bootout system/com.nomachine.uninstall 2>/dev/null
sudo launchctl bootout "gui/$uid/com.nomachine.uninstallAgent" 2>/dev/null
sudo rm -f "$AGENT_PLIST"

# 3. 官方卸载脚本只在应用目录已经不在时才干活：先删应用，再跑它。
#    它负责：停服务、删 launchd 配置、/etc/NX、/etc/pam.d/nx、驱动、安装记录、收回屏幕录制授权等。
sudo rm -rf "$APP"
if [ -f "$VENDOR" ]; then
    ms_log "运行 NoMachine 官方卸载脚本..."
    sudo /bin/bash "$VENDOR" >> "$MS_HOME/nomachine-uninstall.log" 2>&1 \
        || ms_warn "NoMachine 官方卸载脚本报错（日志 $MS_HOME/nomachine-uninstall.log），继续"
else
    ms_warn "找不到 NoMachine 官方卸载脚本，只做下面的补充清理"
fi

# 4. 官方脚本在新系统上交给图形界面做的：删系统用户 nx / nxhtd（连同同名组、隐藏用户列表里的名字）
for u in nx nxhtd; do
    if dscl . -read "/Users/$u" >/dev/null 2>&1; then
        sudo sysadminctl -deleteUser "$u" >/dev/null 2>&1 || sudo dscl . -delete "/Users/$u" 2>/dev/null
        dscl . -read "/Users/$u" >/dev/null 2>&1 && ms_warn "系统用户 $u 没删掉" || ms_log "已删除系统用户 $u"
    fi
    if dscl . -read "/Groups/$u" >/dev/null 2>&1; then
        sudo dscl . -delete "/Groups/$u" 2>/dev/null || ms_warn "组 $u 没删掉"
    fi
    if dscl . -read /Groups/com.apple.access_ssh GroupMembership 2>/dev/null | tr ' ' '\n' | grep -qx "$u"; then
        sudo dscl . -delete /Groups/com.apple.access_ssh GroupMembership "$u" 2>/dev/null
    fi
done
LW=/Library/Preferences/com.apple.loginwindow
if defaults read "$LW" HiddenUsersList >/dev/null 2>&1; then
    keep="$(defaults read "$LW" HiddenUsersList | sed -e '1d' -e '$d' -e 's/[ ",]//g' | grep -vx -e nx -e nxhtd -e '')"
    if [ -n "$keep" ]; then
        # shellcheck disable=SC2086
        sudo defaults write "$LW" HiddenUsersList -array $keep
    elif ms_recorded nm-hidden-list absent; then
        sudo defaults delete "$LW" HiddenUsersList
    else
        sudo defaults write "$LW" HiddenUsersList -array
    fi
fi

# 5. 剩下的支持目录（官方脚本在新系统上也留给图形界面删）和安装记录
sudo rm -rf "$SUPPORT"
for p in $(pkgutil --pkgs 2>/dev/null | grep '^com\.nomachine\.'); do
    sudo pkgutil --forget "$p" >/dev/null 2>&1
done

# 6. 收回给 NoMachine 的系统授权（屏幕录制、辅助功能等，系统级和本用户的都清）
sudo tccutil reset All com.nomachine.nxdock >/dev/null 2>&1
tccutil reset All com.nomachine.nxdock >/dev/null 2>&1
ms_log "NoMachine 的系统级部分已清理"
exit 0
