#!/bin/bash
# 目标机恢复原状：删掉我们装的东西、清掉登录态、把备份的原有配置放回去。
#
#   bash ~/.mac_setup/src/uninstall.sh
#
# 只动清单（~/.mac_setup/manifest.tsv）里记为「我们装的」的东西；原来就有的软件和配置不碰。
# 整个脚本包在 main 里：结尾会删掉 ~/.mac_setup（含本脚本自身），必须先整体读入再执行。
set -uo pipefail

main() {
    local self_dir
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    MS_SRC="$self_dir"
    export MS_SRC
    . "$MS_SRC/lib/common.sh"
    [ -f "$MS_MANIFEST" ] || ms_die "找不到安装清单 ${MS_MANIFEST}，没有可恢复的东西"
    ms_brew_load || true

    # 1. 各模块自己的清理（登录态、应用设置等），按安装的反序
    local d dirs=""
    for d in "$MS_SRC"/modules/*/; do dirs="$d $dirs"; done
    for d in $dirs; do
        if [ -f "$d/uninstall.sh" ]; then
            ms_log "==> 清理模块 $(basename "$d")"
            /bin/bash "$d/uninstall.sh" </dev/null || ms_warn "模块 $(basename "$d") 清理时报错，继续"
        fi
    done

    # 2. 删掉我们创建的文件 / 目录 / 软链接（反序：后创建的先删）
    local p dest
    awk -F'\t' '$1=="path"{print $2}' "$MS_MANIFEST" | tail -r | while IFS= read -r p; do
        ms_log "删除 $p"
        ms_remove_path "$p"
    done

    # 3. 把原有的东西放回去
    awk -F'\t' '$1=="backup"{print $2 "\t" $3}' "$MS_MANIFEST" | tail -r | while IFS="$(printf '\t')" read -r p dest; do
        if [ -e "$dest" ] || [ -L "$dest" ]; then
            if [ -e "$p" ] || [ -L "$p" ]; then
                ms_warn "$p 处还有东西，原件留在 $dest 没有放回"
                touch "$MS_HOME/.keep"
                continue
            fi
            mkdir -p "$(dirname "$p")"
            mv "$dest" "$p" && ms_log "已还原 $p"
        fi
    done

    # 4. 软件：Homebrew 是我们装的 → 整个卸掉；否则只卸我们装的那几个
    if ms_recorded brew /opt/homebrew || ms_recorded brew /usr/local; then
        ms_log "卸载 Homebrew（连同经它安装的全部软件）"
        awk -F'\t' '$1=="cask"{print $2}' "$MS_MANIFEST" | while IFS= read -r p; do
            brew uninstall --cask --zap --force "$p" </dev/null || ms_warn "cask $p 卸载失败"
        done
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" </dev/null \
            || ms_warn "Homebrew 卸载脚本报错"
        if [ -d /opt/homebrew ] && ms_recorded brew /opt/homebrew; then sudo rm -rf /opt/homebrew; fi
    else
        awk -F'\t' '$1=="cask"{print $2}' "$MS_MANIFEST" | while IFS= read -r p; do
            brew uninstall --cask --zap --force "$p" </dev/null || ms_warn "cask $p 卸载失败"
        done
        awk -F'\t' '$1=="formula"{print $2}' "$MS_MANIFEST" | tail -r | while IFS= read -r p; do
            brew uninstall "$p" </dev/null || ms_warn "formula $p 卸载失败"
        done
    fi

    # 5. Xcode 命令行工具是我们（经 Homebrew）装的 → 删掉
    if ms_recorded clt /Library/Developer/CommandLineTools; then
        ms_log "删除 Xcode 命令行工具"
        sudo rm -rf /Library/Developer/CommandLineTools
    fi

    # 6. 清掉我们自己的状态目录
    if [ -f "$MS_HOME/.keep" ]; then
        ms_warn "有原件没能放回，保留 $MS_HOME 供手工处理"
    else
        # 删的是本次用的状态目录（MS_HOME 可能被改过，不能写死 ~/.mac_setup，否则会删错别人的清单）
        case "$MS_HOME" in
            "$HOME"/.mac_setup*) cd /; rm -rf -- "$MS_HOME"; echo "[mac_setup] 已恢复原状。" ;;
            *) ms_warn "状态目录 $MS_HOME 不在预期位置，没有删，请手工处理" ;;
        esac
    fi
}

main "$@"
exit $?
