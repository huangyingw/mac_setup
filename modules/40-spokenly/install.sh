#!/bin/bash
# 语音输入：Spokenly + 本机 Qwen3-ASR 转写服务，设置与参考机一致，模型提前下好、断网也能听写。
#
# 参考机现状（2026-11-13 调查，细节见 docs/decisions/spokenly.md）：
#   - Spokenly 是官网直装版（Homebrew cask 装的就是它）。听写不用它内置的模型，而是调本机常驻的
#     转写服务 http://127.0.0.1:8765（mlx_audio.server，launchd 拉起，模型 Qwen3-ASR）；
#   - 服务的启动脚本、依赖清单、Spokenly 设置的仓库副本都在 voice_input 仓库。那个仓库含个人口述的
#     转写文本，不能公开，所以只导出这里要用的几个文件做成快照（snapshots/voice_input.include）；
#   - 模型取 16GB 内存那一档（voice_input 里 mbp 用的那份：service/model.mbp 与
#     spokenly-settings.mbp.json）。参考机 64GB 用的大模型不照搬。
#
# 不能自动完成、登记为人工事项的：麦克风和辅助功能两项系统授权。Spokenly 不需要登录。
set -euo pipefail
. "$MS_SRC/lib/common.sh"

MOD="$MS_SRC/modules/40-spokenly"
SNAP_SLUG="huangyingw/voice_input-snapshot"
SNAP="$MS_HOME/voice_input"                 # 快照落在状态目录里，恢复原状时随状态目录一起删
DEST="$HOME/.local/share/qwen3-asr-server"  # 服务的运行环境、模型、日志全放这里（与参考机同一位置）
LABEL="com.huangyingw.qwen3-asr"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
PORT=8765
PREFS="$HOME/Library/Preferences/app.spokenly.plist"
KEYCHAIN_SVC="app.spokenly.FSDService"
APP="/Applications/Spokenly.app"

# Spokenly 运行时自己会写的位置。启动它之前全部认领：对方原有的先挪进备份，
# 我用过留下的（含听写录音和历史）恢复原状时直接删掉，不进废纸篓。
APP_STATE="
$PREFS
$HOME/Library/Application Support/Spokenly
$HOME/Library/Application Support/app.spokenly.revenuecat
$HOME/Library/Caches/app.spokenly
$HOME/Library/HTTPStorages/app.spokenly
$HOME/Library/HTTPStorages/app.spokenly.binarycookies
$HOME/Library/WebKit/app.spokenly
$HOME/Library/Saved Application State/app.spokenly.savedState
"

# claim_new_dir <目录>...：原来没有 → 建出来并记为我们的；原来就有 → 不动、不记账
claim_new_dir() {
    local d
    for d in "$@"; do
        [ -e "$d" ] && continue
        ms_record path "$d"
        mkdir -p "$d"
    done
}

# 退出 Spokenly。不用 osascript：它要先过「自动化」授权弹窗，经 ssh 或没人点的时候会卡住。
quit_spokenly() {
    local i=0
    pgrep -x Spokenly >/dev/null 2>&1 || return 0
    pkill -x Spokenly 2>/dev/null || true
    while pgrep -x Spokenly >/dev/null 2>&1; do
        [ "$i" -lt 15 ] || ms_die "Spokenly 没有退出，设置没有改"
        sleep 1; i=$((i + 1))
    done
}

# 设置文件是直接改的，让系统的设置缓存重新读盘（进程会被系统自动拉起）
flush_prefs_cache() { killall -u "$(id -un)" cfprefsd 2>/dev/null || true; }

# ---------- 1. Spokenly 本体 ----------

# 钥匙串：Spokenly 首次启动会写一条自己的记录。原来没有 → 记下来，恢复原状时删掉。
if ! ms_recorded keychain "$KEYCHAIN_SVC" \
        && ! security find-generic-password -s "$KEYCHAIN_SVC" >/dev/null 2>&1; then
    ms_record keychain "$KEYCHAIN_SVC" ours
fi

quit_spokenly
printf '%s\n' "$APP_STATE" | while IFS= read -r p; do
    [ -n "$p" ] || continue
    ms_claim "$p"
done
flush_prefs_cache

ms_cask spokenly Spokenly.app || ms_die "Spokenly 安装失败"
if [ -d "$HOME/Library/Containers/app.spokenly" ] && ! ms_recorded cask spokenly; then
    ms_todo "Spokenly：这台机器原来装的可能是 App Store 版（识别结果不会自动贴进输入框，也读不到我写的设置）；要用的话先告诉机主，再换成官网版"
fi

# 首次打开的确认框（「这是从互联网下载的应用，确定要打开吗」）：没人点的话进程会一直挂在启动前，
# 设置读不进去。只对「我们刚装的、且系统判定为已公证」的这一份免掉这次确认；
# 系统不认可的、或对方原来就有的，一律不动，留给人工点。
if ms_recorded cask spokenly && xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
    if spctl -a -t exec "$APP" >/dev/null 2>&1; then
        xattr -dr com.apple.quarantine "$APP" 2>/dev/null
    fi
fi

# 本机转写服务基于 MLX，只支持 Apple 芯片。（这条分支没有在 Intel 机器上实测过）
if [ "$(uname -m)" != arm64 ]; then
    ms_todo "Spokenly：这台是 Intel 芯片，本机转写服务装不了；应用已装好，打开后按向导在它自己的模型里选一个"
    ms_warn "Intel 芯片：只装了 Spokenly 本体，没有装本机转写服务，也没有写设置"
    exit 0
fi

# ---------- 2. 取 voice_input 快照 ----------

rm -rf "$SNAP.new"
mkdir -p "$SNAP.new"
if curl -fsSL "https://codeload.github.com/$SNAP_SLUG/tar.gz/refs/heads/main" \
        | tar -xz -C "$SNAP.new" --strip-components 1; then
    rm -rf "$SNAP"
    mv "$SNAP.new" "$SNAP"
else
    rm -rf "$SNAP.new"
    [ -f "$SNAP/service/run.sh" ] \
        || ms_die "拉不到 ${SNAP_SLUG}（还没公开？参考机上先跑 local/publish.sh ${SNAP_SLUG}）"
    ms_warn "${SNAP_SLUG} 没能更新到最新（已改回私有？），沿用上次取到的内容"
fi
for f in service/run.sh "service/$LABEL.plist" service/model.mbp eval/requirements.txt \
         service/spokenly-settings.json service/spokenly-settings.mbp.json; do
    [ -f "$SNAP/$f" ] || ms_die "快照里缺 ${f}（参考机上核对 snapshots/voice_input.include）"
done
MODEL="$(tr -d '[:space:]' < "$SNAP/service/model.mbp")"
[ -n "$MODEL" ] || ms_die "快照里的 service/model.mbp 是空的"

# ---------- 3. 本机转写服务 ----------

ms_formula uv || ms_die "uv 安装失败"

claim_new_dir "$HOME/.local" "$HOME/.local/share" "$HOME/Library/LaunchAgents"
ms_claim "$DEST"
mkdir -p "$DEST/logs"

# uv 下载的 Python 和缓存都收在服务目录里，不往家目录别处写
export UV_CACHE_DIR="$DEST/uv-cache"
export UV_PYTHON_INSTALL_DIR="$DEST/python"
export UV_PYTHON_PREFERENCE=only-managed
export UV_PYTHON_INSTALL_BIN=0
# 依赖里有要现场编译的包。装了 Xcode 但没同意许可时编译会失败，固定用独立的命令行工具链
if [ -d /Library/Developer/CommandLineTools ]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

ms_log "安装转写服务的 Python 环境（首次要下载约 1GB，需要几分钟）..."
[ -x "$DEST/.venv/bin/python" ] || uv venv --quiet -p 3.12 "$DEST/.venv"
VIRTUAL_ENV="$DEST/.venv" uv pip install --quiet -r "$SNAP/eval/requirements.txt" \
    || ms_die "转写服务的依赖没装上"

ms_log "下载语音模型 ${MODEL}..."
HF_HOME="$DEST/hf" HF_HUB_OFFLINE=0 "$DEST/.venv/bin/python" -c \
    "import sys; from huggingface_hub import snapshot_download; snapshot_download(sys.argv[1])" "$MODEL" >/dev/null \
    || ms_die "语音模型 ${MODEL} 没下载下来"

printf '%s\n' "$MODEL" > "$DEST/model"
cp "$SNAP/service/run.sh" "$DEST/run.sh"
chmod +x "$DEST/run.sh"

ms_claim "$AGENT"
sed "s|__DEST__|$DEST|g" "$SNAP/service/$LABEL.plist" > "$AGENT"

uid="$(id -u)"
launchctl bootout "gui/$uid/$LABEL" 2>/dev/null || true
# bootout 是异步的，旧服务没退干净就 bootstrap 会失败
i=0
while launchctl print "gui/$uid/$LABEL" >/dev/null 2>&1 && [ "$i" -lt 30 ]; do sleep 1; i=$((i + 1)); done
launchctl bootstrap "gui/$uid" "$AGENT" \
    || ms_die "转写服务没能启动（launchctl bootstrap 失败；没有登录到桌面时会这样）"

ms_log "等转写服务就绪..."
i=0
until curl -fsS -o /dev/null "http://127.0.0.1:$PORT/v1/models" 2>/dev/null; do
    [ "$i" -lt 120 ] || ms_die "转写服务 4 分钟内没有就绪，看日志 ${DEST}/logs/server.log"
    sleep 2; i=$((i + 1))
done

# 自检：让系统朗读一句话，交给服务转写，确认模型真的能用（不经麦克风，不需要任何授权）
wav="$DEST/selftest.wav"
if say -o "$wav" --data-format=LEI16@16000 "This is a dictation test." 2>/dev/null; then
    heard="$(curl -fsS --max-time 300 -F "file=@$wav" --form-string "model=$MODEL" \
        --form-string "response_format=text" "http://127.0.0.1:$PORT/v1/audio/transcriptions")" \
        || ms_die "转写服务自检失败，看日志 ${DEST}/logs/server.log"
    [ -n "$heard" ] || ms_die "转写服务自检没有返回文字，看日志 ${DEST}/logs/server.log"
    ms_log "转写服务自检通过，识别结果：${heard}"
else
    ms_warn "系统朗读不可用，跳过了转写服务自检"
fi
rm -f "$wav"

# ---------- 4. Spokenly 设置 ----------

quit_spokenly
"$DEST/.venv/bin/python" "$MOD/settings.py" apply "$PREFS" \
    "$SNAP/service/spokenly-settings.json" "$SNAP/service/spokenly-settings.mbp.json" \
    || ms_die "Spokenly 设置没写进去"
flush_prefs_cache

open -a Spokenly 2>/dev/null \
    || ms_warn "没能自动打开 Spokenly（没有登录到桌面？），手动从「应用程序」里打开"

if xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
    ms_todo "Spokenly：第一次打开时系统会问「这是从互联网下载的应用，确定要打开吗」，点「打开」（不点的话它不会真正启动）"
fi
ms_todo "Spokenly：按听写快捷键说一句话，系统问麦克风权限时点「允许」"
ms_todo "Spokenly：系统设置 → 隐私与安全性 → 辅助功能，打开 Spokenly 的开关（不开的话识别出的文字不会自动贴进输入框）"

ms_log "Spokenly 已装好，听写走本机转写服务（模型 ${MODEL}）"
