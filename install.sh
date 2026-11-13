#!/bin/bash
# 目标机安装入口。在对方的 Mac 上打开「终端」，贴这一行即可（不需要 git、不需要参考机）：
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/huangyingw/mac_setup/integration/install.sh)"
#
# 只跑某几个模块：   bash ~/.mac_setup/src/install.sh base spokenly
# 事后恢复原状：     bash ~/.mac_setup/src/uninstall.sh
#
# 兼容 macOS 自带 bash 3.2。
set -euo pipefail

MS_SLUG="${MS_SLUG:-huangyingw/mac_setup}"
MS_BRANCH="${MS_BRANCH:-integration}"
MS_HOME="${MS_HOME:-$HOME/.mac_setup}"
export MS_SLUG MS_BRANCH MS_HOME

self_dir=""
case "${BASH_SOURCE[0]:-}" in
    */*) self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" ;;
esac

# 经 curl 直接运行时身边没有仓库文件：先把仓库取到 ~/.mac_setup/src 再从那里重新执行。
# 干净的 macOS 没有 git（要装 Xcode 命令行工具才有），所以用系统自带的 curl + tar 取压缩包。
if [ -z "$self_dir" ] || [ ! -f "$self_dir/lib/common.sh" ] || [ "${MS_REFRESH:-}" = 1 ]; then
    echo "[mac_setup] 下载 $MS_SLUG ($MS_BRANCH) ..."
    mkdir -p "$MS_HOME"
    rm -rf "$MS_HOME/src.new"
    mkdir "$MS_HOME/src.new"
    curl -fsSL "https://codeload.github.com/$MS_SLUG/tar.gz/refs/heads/$MS_BRANCH" \
        | tar -xz -C "$MS_HOME/src.new" --strip-components 1
    rm -rf "$MS_HOME/src"
    mv "$MS_HOME/src.new" "$MS_HOME/src"
    MS_REFRESH="" exec /bin/bash "$MS_HOME/src/install.sh" "$@"
fi

MS_SRC="$self_dir"
export MS_SRC
. "$MS_SRC/lib/common.sh"
ms_state_init

[ "$(uname -s)" = Darwin ] || ms_die "只支持 macOS"

# 选模块：不带参数 = modules/ 下全部，按目录名顺序；带参数 = 只跑点名的（可省略数字前缀）
selected=""
if [ $# -gt 0 ]; then
    for want in "$@"; do
        hit=""
        for d in "$MS_SRC"/modules/*/; do
            n="$(basename "$d")"
            if [ "$n" = "$want" ] || [ "${n#*-}" = "$want" ]; then hit="$n"; fi
        done
        [ -n "$hit" ] || ms_die "没有这个模块: $want"
        selected="$selected $hit"
    done
else
    for d in "$MS_SRC"/modules/*/; do
        [ -f "$d/install.sh" ] && selected="$selected $(basename "$d")"
    done
fi

ok="" failed=""
for name in $selected; do
    ms_log "==> 模块 $name"
    if /bin/bash "$MS_SRC/modules/$name/install.sh" 2>&1 | tee -a "$MS_LOG"; then
        ok="$ok $name"
    else
        failed="$failed $name"
        ms_warn "模块 $name 失败，继续跑后面的模块（日志: ${MS_LOG}）"
    fi
done

echo
ms_log "完成的模块:${ok:- 无}"
[ -z "$failed" ] || ms_warn "失败的模块:$failed"
if [ -s "$MS_TODO" ]; then
    echo
    ms_log "下面这些需要你亲手做："
    awk '{printf "  %d. %s\n", NR, $0}' "$MS_TODO"
fi
echo
ms_log "事后恢复原状: bash $MS_SRC/uninstall.sh"
[ -z "$failed" ]
