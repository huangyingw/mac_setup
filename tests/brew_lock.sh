#!/bin/bash
# 回归测试：同一台机器上几个 mac_setup 进程（各用一个状态目录）同时 brew install 时，一次只跑一个，
# 别人下载的安装包不会记进自己的清单；持有锁的进程被打断后，锁能被接手。
# 在临时目录里用假的 brew 跑，不碰真实的 Homebrew：
#   bash tests/brew_lock.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" MS_BREW_LOCK="$T/brew.lock" C="$T/cache" P="$T/home/brew" root T
mkdir -p "$HOME" "$C/downloads" "$P/etc"

fail=0
ok()  { printf '  通过  %s\n' "$1"; }
bad() { printf '  失败  %s\n' "$1"; fail=1; }

# 假的 brew：install 时记下开始 / 结束，中间往缓存里放自己的安装包，并停一会儿，好让两个进程重叠
brew() {
    case "$1" in
        --cache)  printf '%s\n' "$C" ;;
        --prefix) printf '%s\n' "$P" ;;
        install)
            echo "start $2" >> "$T/events"
            sleep 1; : > "$C/downloads/$2.tar.gz"; sleep 1
            echo "end $2" >> "$T/events" ;;
    esac
}
export -f brew

run() {  # run <状态目录名> <formula>：像一个独立的 mac_setup 进程那样装一个东西
    MS_HOME="$HOME/.mac_setup_$1" /bin/bash -c '. "$root/lib/common.sh"; ms_state_init; ms_brew_install "$0"' "$2"
}

echo "== 两个进程同时装"
run a foo > "$T/a.out" 2>&1 & pa=$!
sleep 0.3
run b bar > "$T/b.out" 2>&1 & pb=$!
wait "$pa"; wait "$pb"
sed 's/^/    | /' "$T/events"
if [ "$(tr '\n' ' ' < "$T/events")" = "start foo end foo start bar end bar " ]; then ok "一次只跑一个"; else bad "两个 brew install 重叠了"; fi
ca="$(awk -F'\t' '$1=="brewcache"{print $2}' "$HOME/.mac_setup_a/manifest.tsv")"
cb="$(awk -F'\t' '$1=="brewcache"{print $2}' "$HOME/.mac_setup_b/manifest.tsv")"
[ "$ca" = "$C/downloads/foo.tar.gz" ] && ok "a 只记了自己的" || bad "a 的清单: $ca"
[ "$cb" = "$C/downloads/bar.tar.gz" ] && ok "b 只记了自己的" || bad "b 的清单: $cb"
grep -q "等这台机器上另一个 mac_setup 的 brew 跑完" "$T/b.out" && ok "后来的说明了在等" || bad "后来的没说在等"
[ -e "$MS_BREW_LOCK" ] && bad "锁没放掉" || ok "锁已放掉"

echo "== 持有者被打断（进程已不在）"
mkdir "$MS_BREW_LOCK"; echo 999999 > "$MS_BREW_LOCK/pid"
: > "$T/events"
( run c baz > "$T/c.out" 2>&1 ) & pc=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pc" 2>/dev/null || break; sleep 1; done
if kill -0 "$pc" 2>/dev/null; then bad "卡在死锁上"; kill "$pc"; else ok "接手了被丢下的锁"; fi
grep -q "end baz" "$T/events" && ok "装完了" || bad "没装"
[ -e "$MS_BREW_LOCK" ] && bad "锁没放掉" || ok "锁已放掉"

echo
if [ "$fail" = 0 ]; then echo "全部通过"; else echo "有失败项"; fi
exit "$fail"
