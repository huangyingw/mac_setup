#!/bin/bash
# 回归测试：Homebrew 原来就有时，我们下载进它缓存的安装包（含依赖的）在恢复原状时被清掉，
# 对方原来就缓存着的、brew 自己运转用的数据不碰。
# 在临时 HOME 里用假的 brew 跑，不碰真实的 Homebrew，参考机 / 目标机上都能跑：
#   bash tests/brew_cache.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
export MS_HOME="$HOME/.mac_setup"
C="$T/cache"                                           # 假的 brew --cache
mkdir -p "$HOME" "$T/src/modules" "$C/downloads" "$C/Cask" "$C/api"
cp -R "$root/lib" "$root/uninstall.sh" "$T/src/"      # 不带各模块的清理脚本，只测框架

fail=0
ok()   { printf '  通过  %s\n' "$1"; }
bad()  { printf '  失败  %s\n' "$1"; fail=1; }
has()  { if [ -e "$1" ] || [ -L "$1" ]; then ok "还在: ${1#$C/}"; else bad "不该被删: ${1#$C/}"; fi; }
gone() { if [ -e "$1" ] || [ -L "$1" ]; then bad "该删没删: ${1#$C/}"; else ok "已删: ${1#$C/}"; fi; }
cached() { awk -F'\t' -v v="$1" '$1=="brewcache" && $2==v {n++} END{print n+0}' "$MS_HOME/manifest.tsv"; }

# 对方原来就缓存着的安装包，以及 brew 自己的数据
: > "$C/downloads/aaa--old.tar.gz"; ln -s downloads/aaa--old.tar.gz "$C/old--1.0"
: > "$C/api/formula.jws.json"

echo "== 安装阶段的记账（Homebrew 原来就有：清单里没有 brew 那一条）"
(
    set -e
    # 假的 brew：install 时像真的一样往缓存里放安装包、链接（formula 带一个依赖），并更新 api/
    brew() {
        case "$1" in
            --cache) printf '%s\n' "$C" ;;
            install)
                : > "$C/api/formula.jws.json"
                if [ "$2" = --cask ]; then
                    : > "$C/downloads/ccc--$3.dmg"; ln -sf "../downloads/ccc--$3.dmg" "$C/Cask/$3--2.0.dmg"
                else
                    : > "$C/downloads/bbb--$2.tar.gz"; ln -sf "downloads/bbb--$2.tar.gz" "$C/$2--1.0"
                    : > "$C/downloads/ddd--dep.tar.gz"; ln -sf downloads/ddd--dep.tar.gz "$C/dep--1.0"
                fi
                [ "$2" != broken ] ;;
        esac
    }
    . "$T/src/lib/common.sh"
    ms_state_init
    ms_brew_install foo
    ms_brew_install --cask app
    if ms_brew_install broken; then exit 1; fi        # 失败要如实返回非 0
) || bad "安装阶段报错"
[ "$(cached "$C/foo--1.0")" = 1 ]                 && ok "formula 的安装包记了"          || bad "formula 的安装包没记"
[ "$(cached "$C/dep--1.0")" = 1 ]                 && ok "依赖的安装包也记了"            || bad "依赖的安装包没记"
[ "$(cached "$C/Cask/app--2.0.dmg")" = 1 ]        && ok "cask 的安装包记了"             || bad "cask 的安装包没记"
[ "$(cached "$C/broken--1.0")" = 1 ]              && ok "安装失败时下载的也记了"        || bad "安装失败时下载的没记"
[ "$(cached "$C/old--1.0")" = 0 ]                 && ok "原来就有的没记"                || bad "原来就有的不该记"
[ "$(cached "$C/api/formula.jws.json")" = 0 ]     && ok "brew 自己的数据没记"           || bad "brew 自己的数据不该记"
if ls "$MS_HOME"/brewcache.* >/dev/null 2>&1; then bad "临时文件没清"; else ok "临时文件已清"; fi

echo "== Homebrew 是我们装的：不记缓存（整个卸掉就行）"
(
    set -e
    brew() { case "$1" in --cache) printf '%s\n' "$C" ;; install) : > "$C/downloads/eee--x.tar.gz" ;; esac; }
    . "$T/src/lib/common.sh"
    MS_HOME="$T/state2"; MS_MANIFEST="$MS_HOME/manifest.tsv"; MS_BACKUP_DIR="$MS_HOME/backup"; MS_TODO="$MS_HOME/todo"
    ms_state_init
    ms_record brew /opt/homebrew
    ms_brew_install x
    ! grep -q '^brewcache' "$MS_MANIFEST"
) && ok "没有记 brewcache" || bad "Homebrew 是我们装的时不该记 brewcache"
rm -f "$C/downloads/eee--x.tar.gz"

echo "== 恢复原状"
/bin/bash "$T/src/uninstall.sh" > "$T/out.txt" 2>&1 || bad "uninstall.sh 退出码非 0"
sed 's/^/    | /' "$T/out.txt"

gone "$C/foo--1.0";  gone "$C/downloads/bbb--foo.tar.gz"
gone "$C/dep--1.0";  gone "$C/downloads/ddd--dep.tar.gz"
gone "$C/Cask/app--2.0.dmg"; gone "$C/downloads/ccc--app.dmg"
gone "$C/broken--1.0"; gone "$C/downloads/bbb--broken.tar.gz"
has  "$C/old--1.0";  has  "$C/downloads/aaa--old.tar.gz"
has  "$C/api/formula.jws.json"
has  "$C/Cask"; has "$C/downloads"

echo
if [ "$fail" = 0 ]; then echo "全部通过"; else echo "有失败项"; fi
exit "$fail"
