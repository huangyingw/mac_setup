#!/bin/bash
# 参考机上运行：从一个不能公开的仓库导出「只含需要的文件、不带历史」的快照，推到快照仓库。
#
#   local/snapshot.sh <快照名> <GitHub 快照仓库>      （通常由 publish.sh 调用）
#
# 读 snapshots/<名>.conf（SRC=原仓库本地检出，REF=导出哪个提交）
# 和 snapshots/<名>.include（要导出的路径前缀，一行一个，不支持通配符；以 ! 开头的行是排除）。
# 路径里的子模块按原仓库记录的提交带过去，URL 改成 https；匿名拉不到的子模块会报错。
# 导出的文件先过密钥检查，不过就不提交、不推送。快照仓库不存在时建成 private。
# SNAPSHOT_LOCAL_ONLY=1：只在本地生成和检查，不建仓库、不推送（调试导出范围时用）。
set -euo pipefail
. "$(dirname "$0")/lib.sh"
need gh; need git; need gitleaks

name="${1:?用法: snapshot.sh <快照名> <GitHub 快照仓库>}"
slug="${2:?用法: snapshot.sh <快照名> <GitHub 快照仓库>}"
guard_slug "$slug"
conf="$ROOT/snapshots/$name.conf"; inc="$ROOT/snapshots/$name.include"
[ -f "$conf" ] || die "缺少 $conf"
[ -f "$inc" ] || die "缺少 $inc"
SRC=""; REF=""
. "$conf"
SRC="$(expand_path "$SRC")"
[ -n "$REF" ] || die "$conf 没有设 REF"

# 要导出 / 排除的路径 → git pathspec
specs=()
while IFS= read -r line; do
    line="${line%%#*}"; line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "$line" ] || continue
    case "$line" in
        !*) specs+=(":(exclude)${line#!}") ;;
        *)  specs+=("$line") ;;
    esac
done < "$inc"
[ ${#specs[@]} -gt 0 ] || die "$inc 里没有任何路径"

git -C "$SRC" fetch --quiet origin || die "$SRC: git fetch 失败"
src_sha="$(git -C "$SRC" rev-parse "$REF")"

work="$(snapshot_workdir "$name")"
local_only="${SNAPSHOT_LOCAL_ONLY:-}"
if [ -n "$local_only" ]; then
    [ -d "$work/.git" ] || { mkdir -p "$work"; git -C "$work" init --quiet -b main; }
elif [ ! -d "$work/.git" ]; then
    if [ -z "$(visibility "$slug")" ]; then
        info "创建 private 仓库 $slug"
        gh repo create "$slug" --private --description "mac_setup 用的快照，自动生成，勿手改" >/dev/null
    fi
    mkdir -p "$(dirname "$work")"
    git clone --quiet "git@github.com:$slug.git" "$work"
    git -C "$work" symbolic-ref HEAD refs/heads/main
else
    [ -z "$(git -C "$work" ls-remote --heads origin main)" ] || git -C "$work" pull --quiet origin main
fi

# 清空后重新导出，保证快照只含清单里的东西
git -C "$work" rm -rq --ignore-unmatch . >/dev/null 2>&1 || true
git -C "$work" clean -fdxq
git -C "$SRC" archive "$src_sha" -- "${specs[@]}" | tar -x -C "$work"
rm -f "$work/.gitmodules"

# 子模块：原仓库在导出范围内记录的 gitlink，按原提交带过去。
# （ls-tree 不认排除写法，所以列出全部 gitlink，再按 .include 的路径前缀自己判断）
in_scope() {
    local p="$1" s hit=1
    for s in "${specs[@]}"; do
        case "$s" in
            ":(exclude)"*) s="${s#:(exclude)}"; s="${s%/}"
                case "$p" in "$s"|"$s"/*) return 1 ;; esac ;;
            *) s="${s%/}"
                case "$p" in "$s"|"$s"/*) hit=0 ;; esac ;;
        esac
    done
    return $hit
}
sub_bad=0; subs=""
while read -r _mode _type sha path; do
    [ "$_type" = commit ] || continue
    in_scope "$path" || continue
    key="$(git -C "$SRC" config --blob "$src_sha:.gitmodules" --get-regexp '^submodule\..*\.path$' \
            | awk -v p="$path" '$2==p {sub(/\.path$/,"",$1); print $1}')"
    url="$(git -C "$SRC" config --blob "$src_sha:.gitmodules" --get "$key.url")"
    url="$(printf '%s' "$url" | sed -E 's#^git@([^:]+):#https://\1/#')"
    if ! GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote "$url" >/dev/null 2>&1; then
        warn "子模块 ${path}（${url}）匿名拉不到——要么在 .include 里用 !$path 排除，要么把它登记进 repos.txt"
        sub_bad=1; continue
    fi
    rmdir "$work/$path" 2>/dev/null || true
    git -C "$work" config -f .gitmodules "submodule.$path.path" "$path"
    git -C "$work" config -f .gitmodules "submodule.$path.url" "$url"
    subs="$subs$sha $path
"
done <<TREE
$(git -C "$SRC" ls-tree -r "$src_sha")
TREE
[ "$sub_bad" = 0 ] || die "有子模块拉不到，快照没有提交。"

printf '由 mac_setup 的 local/snapshot.sh 自动生成，勿手改。\n来源提交: %s\n' "$src_sha" > "$work/SNAPSHOT_SOURCE"

info "检查快照内容（$(cd "$work" && find . -path ./.git -prune -o -type f -print | wc -l | tr -d ' ') 个文件）"
scan_tree "$work" || die "快照内容没通过密钥检查，没有提交、没有推送。把问题文件从 snapshots/$name.include 里排除后重跑。"

git -C "$work" add -A
while read -r sha path; do
    [ -n "$sha" ] || continue
    git -C "$work" update-index --add --cacheinfo "160000,$sha,$path"
done <<SUBS
$subs
SUBS
if git -C "$work" diff --cached --quiet; then
    info "快照没有变化（来源 ${src_sha:0:9}）"
else
    git -C "$work" commit --quiet -m "snapshot of ${src_sha:0:12}"
    info "快照已更新（来源 ${src_sha:0:9}）"
fi
if [ -n "$local_only" ]; then
    info "只在本地生成，没有推送：$work"
else
    git -C "$work" push --quiet origin HEAD:main
fi
