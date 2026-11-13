#!/bin/bash
# 参考机上运行：把 repos.txt 里的仓库改成 public，供目标机匿名拉取。
#
#   local/publish.sh              # 清单里全部
#   local/publish.sh <仓库>...    # 只公开点名的（必须在清单里）
#
# 先对每个仓库做密钥检查，**全部通过才开始改**；任何一个不过，一个都不改。
# 装完务必跑 local/unpublish.sh 改回 private。
set -euo pipefail
. "$(dirname "$0")/lib.sh"
need gh; need git; need gitleaks

todo=""
while read -r slug mode arg; do
    if [ $# -gt 0 ]; then
        hit=""; for w in "$@"; do [ "$w" = "$slug" ] && hit=1; done
        [ -n "$hit" ] || continue
    fi
    todo="$todo$slug $mode $arg
"
done <<LIST
$(each_repo)
LIST
[ -n "$todo" ] || die "没有要公开的仓库（参数不在 repos.txt 里？）"

info "第 1 步：密钥检查"
bad=0
while read -r slug mode arg; do
    [ -n "$slug" ] || continue
    guard_slug "$slug"
    info "检查 ${slug}（${mode}）"
    case "$mode" in
        direct)
            path="$(expand_path "$arg")"
            [ -d "$path/.git" ] || [ -f "$path/.git" ] || die "$slug: 本地检出 $path 不存在"
            git -C "$path" remote get-url origin | grep -q "[:/]$slug\(\.git\)\{0,1\}$" \
                || die "$slug: $path 的 origin 不是这个仓库"
            scan_history "$path" || bad=1
            ;;
        snapshot)
            "$ROOT/local/snapshot.sh" "$arg" "$slug" || { bad=1; continue; }
            scan_history "$(snapshot_workdir "$arg")" || bad=1
            ;;
        *) die "$slug: 不认识的方式 $mode" ;;
    esac
done <<LIST
$todo
LIST
[ "$bad" = 0 ] || die "密钥检查没通过，一个仓库都没有改。"

info "第 2 步：改成 public"
while read -r slug mode arg; do
    [ -n "$slug" ] || continue
    if [ "$(visibility "$slug")" = PUBLIC ]; then
        warn "$slug 已经是 public（上一次窗口没关？）"
    else
        gh repo edit "$slug" --visibility public --accept-visibility-change-consequences >/dev/null
    fi
    [ "$(visibility "$slug")" = PUBLIC ] || die "$slug 没能改成 public"
    info "  ✓ $slug 已公开"
done <<LIST
$todo
LIST

echo
info "目标机上打开终端，贴这一行："
echo '  bash -c "$(curl -fsSL https://raw.githubusercontent.com/huangyingw/mac_setup/integration/install.sh)"'
echo
warn "装完立刻跑 local/unpublish.sh 改回 private。"
