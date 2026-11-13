#!/bin/bash
# 回归测试：共用的上级目录在恢复原状时「空了才删」，别人后放进去的东西不碰。
# 在临时 HOME 里跑，不碰真实环境，参考机 / 目标机上都能跑：
#   bash tests/shared_dirs.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
export MS_HOME="$HOME/.mac_setup"
mkdir -p "$HOME" "$T/src/modules"
cp -R "$root/lib" "$root/uninstall.sh" "$T/src/"      # 不带各模块的清理脚本，只测框架

fail=0
ok()   { printf '  通过  %s\n' "$1"; }
bad()  { printf '  失败  %s\n' "$1"; fail=1; }
has()  { if [ -e "$1" ]; then ok "还在: ${1#$HOME/}"; else bad "不该被删: ${1#$HOME/}"; fi; }
gone() { if [ -e "$1" ] || [ -L "$1" ]; then bad "该删没删: ${1#$HOME/}"; else ok "已删: ${1#$HOME/}"; fi; }
rec()  { awk -F'\t' -v t="$1" -v v="$2" '$1==t && $2==v {n++} END{print n+0}' "$MS_HOME/manifest.tsv"; }

echo "== 安装阶段的记账"
mkdir -p "$HOME/.config"                               # 机主原来就有的
(
    set -e
    . "$T/src/lib/common.sh"
    ms_state_init
    ms_claim_dir "$HOME/.local/share" "$HOME/.config" "$HOME/.cache" "$HOME/.local/state"
    ms_claim_dir "$HOME/.local/share"                  # 重跑不重复记
    ms_claim "$HOME/.local/share/ours";  mkdir "$HOME/.local/share/ours"; : > "$HOME/.local/share/ours/f"
    ms_claim "$HOME/.config/ours.conf";  : > "$HOME/.config/ours.conf"
    ms_own_if_absent "$HOME/.cache/tool-cache"         # 工具以后自己会写的位置
    # 老写法：把共用目录记成 path（保险要兜住）
    mkdir -p "$HOME/Library/LaunchAgents"
    ms_record path "$HOME/Library"
    ms_record path "$HOME/Library/LaunchAgents"
    ms_claim "$HOME/Library/LaunchAgents/ours.plist"; : > "$HOME/Library/LaunchAgents/ours.plist"
) || bad "安装阶段报错"
[ "$(rec newdir "$HOME/.local")" = 1 ]        && ok "中间缺的 .local 也记了 newdir" || bad ".local 没记 newdir"
[ "$(rec newdir "$HOME/.local/share")" = 1 ]  && ok ".local/share 记了一次 newdir"  || bad ".local/share 记账次数不对"
[ "$(rec newdir "$HOME/.config")" = 0 ]       && ok "原来就有的 .config 没记账"     || bad ".config 不该记账"

echo "== 安装之后：别的程序往这些目录里放东西，我们的工具也写了缓存"
: > "$HOME/.local/share/foreign.txt"
: > "$HOME/Library/LaunchAgents/other.plist"
mkdir "$HOME/.cache/tool-cache"; : > "$HOME/.cache/tool-cache/x"
: > "$HOME/.cache/.DS_Store"

echo "== 恢复原状"
/bin/bash "$T/src/uninstall.sh" > "$T/out.txt" 2>&1 || bad "uninstall.sh 退出码非 0"
sed 's/^/    | /' "$T/out.txt"

gone "$HOME/.local/share/ours"
has  "$HOME/.local/share/foreign.txt"
has  "$HOME/.local"
gone "$HOME/.local/state"
gone "$HOME/.cache"
gone "$HOME/.config/ours.conf"
has  "$HOME/.config"
gone "$HOME/Library/LaunchAgents/ours.plist"
has  "$HOME/Library/LaunchAgents/other.plist"
has  "$HOME/Library"
gone "$MS_HOME"
grep -q "保留 $HOME/.local/share：.*foreign.txt" "$T/out.txt" && ok "说出了 .local/share 里还剩什么" || bad "没说出还剩什么"

if [ "$fail" = 0 ]; then echo "全部通过"; else echo "有失败项"; fi
exit "$fail"
