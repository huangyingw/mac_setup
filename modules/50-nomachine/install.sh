#!/bin/bash
# 远程图形连接：NoMachine。装好后从别的机器用 NoMachine 客户端连这台机器（NX 协议，端口 4000），
# 用这台机器的账号和登录密码登录，看到的是它的实际桌面。
#
# 参考机现状与取舍（2026-11-13 调查，细节见 docs/decisions/nomachine.md）：
#   - 参考机装的是 9.10.3 免费版；服务端配置 server.cfg / node.cfg 与安装包自带的完全相同
#     （同目录的 .backup 是安装时的原样，没有差异），所以这里不改任何配置；
#   - 免费的服务端从 10 版起停了，官网只剩 10.x「Personal Edition」，9.x 已经下不到；Homebrew 的
#     cask `nomachine` 还指着已下架的 9.8.2_1，装不上。所以这里从官网下载页取当前版本的安装包，
#     核对页面给的 MD5 和苹果开发者签名后用系统的 installer 装；
#   - 10.x 不激活不接受连接：要用订阅或 14 天试用许可激活。许可只能在 nomachine.com 登录账号后生成，
#     登记为人工事项；
#   - 系统授权：参考机上「屏幕与系统录音」和「辅助功能」都给了 NoMachine（com.nomachine.nxdock）。
#     脚本给不了，登记为人工事项——不授权的话连上去只看得到桌面背景、鼠标键盘也不起作用。
#
# 安装包会改动的系统位置（恢复原状时由 uninstall.sh 调官方卸载脚本清掉）：
#   /Applications/NoMachine.app、/Library/Application Support/NoMachine、/Library/LaunchDaemons 与
#   /Library/LaunchAgents 下的 com.nomachine.*、/etc/NX、/etc/pam.d/nx、/Library/Audio/Plug-Ins/HAL 下的
#   NMAudio*.driver、隐藏的系统用户 nx（和组 nx）、安装记录 com.nomachine.*。
set -euo pipefail
. "$MS_SRC/lib/common.sh"

APP="/Applications/NoMachine.app"
NXD="$APP/Contents/Frameworks/bin/nxd"
PORT=4000
FW=/usr/libexec/ApplicationFirewall/socketfilterfw
PAGE="https://download.nomachine.com/download/?id=117&platform=mac"   # 官网「NoMachine Personal Edition for Mac」
TEAM="NoMachine S.a.r.l. (493C5JZAGR)"                                 # 安装包签名里的开发者（含苹果团队 ID）
DMG="$MS_HOME/nomachine.dmg"   # 下载的安装包和挂载点放在状态目录里，恢复原状时随状态目录一起删
MNT="$MS_HOME/nomachine-mnt"

# 我们装的记为 nm-pkg（不经 Homebrew，框架不会替我们卸，由本模块的 uninstall.sh 负责）
ours() { ms_recorded nm-pkg "$APP"; }

# 对方原来就装着 NoMachine：不动它，也不碰它的配置和用户数据
if [ -d "$APP" ] && ! ours; then
    ms_log "NoMachine 原来就有，不动（配置也不改）"
    ms_todo "NoMachine：这台机器原来就装着，没有改它的设置；能不能从别的机器连进来取决于机主原来的配置"
    exit 0
fi

if ! ours; then
    # NoMachine 运行时会往当前用户家目录写的位置。装之前认领：原有的先挪进备份，
    # 我们用过留下的（连接记录、日志、录像和收到的文件）恢复原状时直接删掉，不进废纸篓。
    for p in \
        "$HOME/.nx" \
        "$HOME/Documents/NoMachine" \
        "$HOME/Library/Preferences/com.nomachine.nxdock.plist" \
        "$HOME/Library/Saved Application State/com.nomachine.nxdock.savedState"; do
        ms_claim "$p"
    done

    # 应用目录已经不在、但系统里还留着以前装 NoMachine 的残余（对方卸得不干净）：照装，提醒一句。
    if [ -d /etc/NX ] || dscl . -read /Users/nx >/dev/null 2>&1; then
        ms_warn "这台机器上有以前装过 NoMachine 的残余（/etc/NX 或系统用户 nx），恢复原状时会一并清掉"
    fi

    # 安装包会把它建的系统用户 nx 加进登录窗口的「隐藏用户列表」。这个列表原来没有 → 记账，
    # 恢复原状时整项删掉，而不是留一个空列表。
    if ! defaults read /Library/Preferences/com.apple.loginwindow HiddenUsersList >/dev/null 2>&1; then
        ms_record nm-hidden-list absent
    fi

    # ---------- 下载官方安装包并核对 ----------
    ms_log "查 NoMachine 官网当前的 macOS 安装包..."
    page="$(curl -fsSL "$PAGE")" || ms_die "打不开 NoMachine 下载页 $PAGE"
    url="$(printf '%s' "$page" | grep -oE 'https://[a-z0-9.]*nomachine\.com/download/[^"<> ]*/MacOSX/nomachine[a-z-]*_[0-9._]+\.dmg' \
        | grep -v -e player -e enterprise | head -1)"
    md5="$(printf '%s' "$page" | sed 's/<[^>]*>/ /g' | tr -s ' \n\t' ' ' \
        | sed -n 's/.*MD5 signature: *\([0-9a-f]\{32\}\).*/\1/p' | head -1)"
    [ -n "$url" ] || ms_die "NoMachine 下载页上没找到 macOS 安装包的地址（页面改版了？看 $PAGE）"
    ms_log "下载 ${url##*/}（约 100MB）..."
    curl -fsSL --retry 3 -o "$DMG" "$url" || ms_die "NoMachine 安装包下载失败：$url"
    if [ -n "$md5" ]; then
        [ "$(md5 -q "$DMG")" = "$md5" ] || ms_die "NoMachine 安装包的 MD5 和下载页上写的不一致，不装"
    else
        ms_warn "下载页上没找到 MD5，只核对签名"
    fi

    hdiutil detach -quiet "$MNT" 2>/dev/null || true
    mkdir -p "$MNT"
    hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MNT" "$DMG" </dev/null \
        || ms_die "NoMachine 安装包打不开（hdiutil attach 失败）"
    pkg="$(find "$MNT" -maxdepth 1 -name '*.pkg' | head -1)"
    if [ -z "$pkg" ]; then hdiutil detach -quiet "$MNT"; ms_die "NoMachine 安装包里没找到 .pkg"; fi

    # 签名必须是 NoMachine 的开发者证书、经苹果公证（系统认可可以安装）
    if ! pkgutil --check-signature "$pkg" 2>/dev/null | grep -Fq "Developer ID Installer: $TEAM" \
            || ! spctl -a -t install "$pkg" >/dev/null 2>&1; then
        hdiutil detach -quiet "$MNT"
        ms_die "NoMachine 安装包的签名不对（不是 $TEAM 的、或没经苹果认可），不装"
    fi

    # 先记账再安装：装到一半被打断，恢复原状时也知道要清
    ms_record nm-pkg "$APP"
    ms_log "安装 NoMachine（要管理员权限）..."
    sudo installer -pkg "$pkg" -target / </dev/null >/dev/null || { hdiutil detach -quiet "$MNT"; ms_die "NoMachine 安装失败"; }
    hdiutil detach -quiet "$MNT" || true
    rm -rf "$MNT" "$DMG"
fi
[ -d "$APP" ] || ms_die "装完找不到 $APP"

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

# 安装包装完会自己拉起服务。等它在 4000 端口上开始监听（等了 2 分钟还没有就重启一次服务）。
ms_log "等 NoMachine 服务就绪..."
i=0
until nc -z -G 2 127.0.0.1 "$PORT" >/dev/null 2>&1; do
    if [ "$i" -eq 60 ]; then sudo /etc/NX/nxserver --restart >/dev/null 2>&1 || true; fi
    [ "$i" -lt 90 ] || ms_die "NoMachine 服务 3 分钟内没有在 ${PORT} 端口监听（看 sudo /etc/NX/nxserver --status）"
    sleep 2; i=$((i + 1))
done
ms_log "NoMachine 服务已在 ${PORT} 端口监听"

# 许可：10.x 不激活不接受连接
if sudo /etc/NX/nxserver --subscription 2>/dev/null | grep -qiE 'expired|not (valid|active|activated)|no (valid )?subscription|invalid'; then
    licensed=""
elif sudo /etc/NX/nxserver --subscription >/dev/null 2>&1; then
    licensed=1
else
    licensed=""
fi
if [ -z "$licensed" ]; then
    ms_todo "NoMachine：要先激活才能连进来——在 nomachine.com 登录账号，User Area → Software → Evaluations 生成 14 天试用许可（或用订阅），然后在这台机器上运行 sudo /etc/NX/nxserver --subscriptionset <许可码或 server.lic 的路径>，用 sudo /etc/NX/nxserver --subscription 确认"
fi

host="$(scutil --get LocalHostName 2>/dev/null || hostname -s).local"
ips="$(ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {printf "%s ", $2}')"
ms_todo "NoMachine：系统设置 → 隐私与安全性 → 「屏幕与系统录音」和「辅助功能」，都打开 NoMachine 的开关（不开的话连上去只看得到桌面背景，鼠标键盘也不起作用）；这一步要在这台机器跟前做"
ms_todo "NoMachine：在别的机器上打开 NoMachine 客户端，连 ${host}（端口 ${PORT}；连不上就用 IP），用这台机器的账号 $(id -un) 和它的登录密码登录"

ms_log "NoMachine 已装好：从别的机器连 ${host} 或 ${ips% }（端口 ${PORT}）"
