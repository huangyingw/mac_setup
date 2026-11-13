#!/bin/bash
# 参考机上运行：把 repos.txt 里的每一个仓库改回 private，并逐个核对。
# 不接受参数——收口永远针对整份清单，避免漏掉某一个。
# 退出码 0 = 全部确认是 private；非 0 = 至少有一个没确认，必须人工处理。
set -uo pipefail
. "$(dirname "$0")/lib.sh"
need gh

bad=0
while read -r slug mode arg; do
    [ -n "$slug" ] || continue
    v="$(visibility "$slug")"
    if [ -z "$v" ]; then
        if [ "$mode" = snapshot ]; then info "  - $slug 还不存在，跳过"; continue; fi
        warn "$slug 查不到可见性"; bad=1; continue
    fi
    if [ "$v" != PRIVATE ]; then
        gh repo edit "$slug" --visibility private --accept-visibility-change-consequences >/dev/null \
            || warn "$slug 改 private 的命令报错"
        v="$(visibility "$slug")"
    fi
    if [ "$v" = PRIVATE ]; then
        info "  ✓ $slug 是 private"
    else
        warn "$slug 现在是 ${v:-未知}，没有回到 private！"; bad=1
    fi
done <<LIST
$(each_repo)
LIST

if [ "$bad" = 0 ]; then info "全部仓库已确认是 private。"; else die "有仓库没有回到 private，见上。"; fi
