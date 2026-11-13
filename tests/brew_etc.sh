#!/bin/bash
# 回归测试：Homebrew 原来就有时，我们装的 formula（含依赖）放进 $(brew --prefix)/etc 的配置文件
# 在恢复原状时被清掉；对方原来就有的、还装着的 formula 仍在用的不碰。
# 在临时 HOME 里用假的 brew 跑，不碰真实的 Homebrew，参考机 / 目标机上都能跑：
#   bash tests/brew_etc.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
export MS_HOME="$HOME/.mac_setup"
P="$HOME/brew"                                         # 假的 brew --prefix（放在家目录下，ms_remove_path 才肯删）
mkdir -p "$P/etc" "$P/Cellar" "$T/cache"
export P T

fail=0
ok()   { printf '  通过  %s\n' "$1"; }
bad()  { printf '  失败  %s\n' "$1"; fail=1; }
has()  { if [ -e "$1" ] || [ -L "$1" ]; then ok "还在: ${1#$P/}"; else bad "不该被删: ${1#$P/}"; fi; }
gone() { if [ -e "$1" ] || [ -L "$1" ]; then bad "该删没删: ${1#$P/}"; else ok "已删: ${1#$P/}"; fi; }
etcrec() { awk -F'\t' -v v="$1" '$1=="brewetc" && $2==v {n++} END{print n+0}' "$MS_HOME/manifest.tsv"; }

# 假的 brew：install foo 时像真的一样连带装两个依赖，各自在 keg 的 .bottle/etc 和 prefix/etc 放配置
brew() {
    case "$1" in
        --prefix) printf '%s\n' "$P" ;;
        --cellar) printf '%s\n' "$P/Cellar" ;;
        --cache)  printf '%s\n' "$T/cache" ;;
        install)
            local d
            for d in sslx cax; do
                mkdir -p "$P/Cellar/$d/1.0/.bottle/etc/$d" "$P/etc/$d"
                : > "$P/Cellar/$d/1.0/.bottle/etc/$d/cert.pem"; : > "$P/etc/$d/cert.pem"
            done
            : > "$P/etc/owner.conf.new-by-brew"; rm -f "$P/etc/owner.conf.new-by-brew"   # 对原有条目的改动不算新条目
            [ "$2" != broken ] ;;
    esac
}

: > "$P/etc/owner.conf"                                 # 对方原来就有的配置
mkdir -p "$P/etc/gitconfig.d"

echo "== 安装阶段的记账（Homebrew 原来就有：清单里没有 brew 那一条）"
(
    set -e
    . "$root/lib/common.sh"
    ms_state_init
    ms_brew_install foo
) || bad "安装阶段报错"
[ "$(etcrec "$P/etc/sslx")" = 1 ]      && ok "依赖放进 etc 的配置记了"   || bad "sslx 没记"
[ "$(etcrec "$P/etc/cax")" = 1 ]       && ok "另一个依赖的也记了"        || bad "cax 没记"
[ "$(etcrec "$P/etc/owner.conf")" = 0 ] && ok "原来就有的没记"           || bad "owner.conf 不该记"
if ls "$MS_HOME"/brewetc.* >/dev/null 2>&1; then bad "临时文件没清"; else ok "临时文件已清"; fi

echo "== Homebrew 是我们装的：不记（整个卸掉就行）"
(
    set -e
    . "$root/lib/common.sh"
    MS_HOME="$T/state2"; MS_MANIFEST="$MS_HOME/manifest.tsv"; MS_BACKUP_DIR="$MS_HOME/backup"; MS_TODO="$MS_HOME/todo"
    ms_state_init
    ms_record brew /opt/homebrew
    rm -rf "$P/etc/sslx"
    ms_brew_install foo
    ! grep -q '^brewetc' "$MS_MANIFEST"
) && ok "没有记 brewetc" || bad "Homebrew 是我们装的时不该记 brewetc"

echo "== brew --prefix 拿不到：什么都不记（不能退化成去比较 /etc）"
(
    set -e
    brew() { case "$1" in install) : ;; esac; }
    . "$root/lib/common.sh"
    MS_HOME="$T/state3"; MS_MANIFEST="$MS_HOME/manifest.tsv"; MS_BACKUP_DIR="$MS_HOME/backup"; MS_TODO="$MS_HOME/todo"
    ms_state_init
    ms_brew_install foo
    [ -z "$(ms_brew_etc_list)" ]
    ! grep -q '^brewetc' "$MS_MANIFEST"
) && ok "没有记 brewetc" || bad "prefix 为空时不该记"

echo "== 恢复原状：sslx 已随 formula 卸掉；cax 后来被对方的 formula 用上了，还装着"
rm -rf "$P/Cellar/sslx"
(
    set -e
    . "$root/lib/common.sh"
    ms_brew_etc_cleanup
) > "$T/out.txt" 2>&1 || bad "ms_brew_etc_cleanup 报错"
sed 's/^/    | /' "$T/out.txt"
gone "$P/etc/sslx"
has  "$P/etc/cax"
has  "$P/etc/owner.conf"
has  "$P/etc/gitconfig.d"
grep -q "保留 $P/etc/cax：还装着的 cax 也用它" "$T/out.txt" && ok "说明了为什么保留" || bad "没说明为什么保留"

echo
if [ "$fail" = 0 ]; then echo "全部通过"; else echo "有失败项"; fi
exit "$fail"
