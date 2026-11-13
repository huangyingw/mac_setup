#!/bin/bash
# 参考机上运行：从一个不能公开的仓库导出「只含需要的文件、不带历史」的快照，推到快照仓库。
#
#   local/snapshot.sh <快照名> <GitHub 快照仓库>      （通常由 publish.sh 调用）
#
# 读 snapshots/<名>.conf（SRC=原仓库本地检出，REF=导出哪个提交）
# 和 snapshots/<名>.include。.include 一行一个路径前缀（不支持通配符），四种写法：
#   路径          导出这个路径。路径下的子模块按原仓库记录的提交、以子模块的形式带过去
#                 （URL 改成 https；匿名拉不到的会报错）
#   子模块/里面的路径   只取该子模块里的这些文件，直接并进快照（不带子模块的历史）
#   @子模块路径   把整个子模块的文件直接并进快照（不带历史），用于匿名拉不到的子模块
#   !路径         排除（也可以写子模块里面的路径）
# 后两种「并进快照」的文件取自 SRC 里该子模块的本地检出、原仓库记录的那个提交，不联网。
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

# 读 .include：普通路径 / 排除（!）/ 整个子模块并进来（@）
incs=(); excs=(); inls=()
while IFS= read -r line; do
    line="${line%%#*}"; line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "$line" ] || continue
    case "$line" in
        !*) line="${line#!}"; excs+=("${line%/}") ;;
        @*) line="${line#@}"; inls+=("${line%/}") ;;
        *)  incs+=("${line%/}") ;;
    esac
done < "$inc"
[ $(( ${#incs[@]} + ${#inls[@]} )) -gt 0 ] || die "$inc 里没有任何路径"

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

TAB="$(printf '\t')"
# 原仓库在这个提交记录的全部子模块，每行「提交<TAB>路径」
links="$(git -C "$SRC" ls-tree -r "$src_sha" | awk -F'\t' '{split($1,a," "); if (a[2]=="commit") print a[3] "\t" $2}')"

# link_of <路径>：这条路径是不是某个子模块本身或在它里面 → 输出「提交<TAB>子模块路径」
link_of() {
    local p="$1" sha g
    while IFS="$TAB" read -r sha g; do
        [ -n "$g" ] || continue
        case "$p" in "$g"|"$g"/*) printf '%s\t%s\n' "$sha" "$g"; return 0 ;; esac
    done <<LINKS
$links
LINKS
    return 1
}

# 把 .include 的每一行分到「原仓库自己的路径」和「某个子模块里面的路径」两边。
# sub_items 每行「子模块路径<TAB>相对它的 pathspec」。
main_incs=(); main_excs=(); sub_items=""
for p in ${incs[@]+"${incs[@]}"}; do
    if o="$(link_of "$p")" && g="${o#*$TAB}" && [ "$p" != "$g" ]; then
        sub_items="$sub_items$g$TAB${p#"$g"/}
"
    else
        main_incs+=("$p")
    fi
done
for p in ${inls[@]+"${inls[@]}"}; do
    o="$(link_of "$p")" || die "$inc: @$p 不是子模块（@ 只能写在子模块路径上）"
    [ "$p" = "${o#*$TAB}" ] || die "$inc: @$p 在子模块 ${o#*$TAB} 里面——取其中一部分直接写路径，不加 @"
    sub_items="$sub_items$p$TAB.
"
done
for p in ${excs[@]+"${excs[@]}"}; do
    if o="$(link_of "$p")" && g="${o#*$TAB}" && [ "$p" != "$g" ]; then
        sub_items="$sub_items$g$TAB:(exclude)${p#"$g"/}
"
    else
        main_excs+=("$p")
    fi
done
# 要把文件并进快照的子模块（有至少一条非排除的路径）
inline_subs="$(printf '%s' "$sub_items" | awk -F'\t' '$2 !~ /^:\(exclude\)/ {print $1}' | sort -u)"
is_inline() { printf '%s\n' "$inline_subs" | grep -Fqx -- "$1"; }

# 清空后重新导出，保证快照只含清单里的东西
git -C "$work" rm -rq --ignore-unmatch . >/dev/null 2>&1 || true
git -C "$work" clean -fdxq
if [ ${#main_incs[@]} -gt 0 ]; then
    specs=("${main_incs[@]}")
    for p in ${main_excs[@]+"${main_excs[@]}"}; do specs+=(":(exclude)$p"); done
    git -C "$SRC" archive "$src_sha" -- "${specs[@]}" | tar -x -C "$work"
fi
rm -f "$work/.gitmodules"

# 子模块里的文件并进快照：取本地检出里、原仓库记录的那个提交
inlined=""
while IFS= read -r g; do
    [ -n "$g" ] || continue
    o="$(link_of "$g")"; sha="${o%%$TAB*}"
    sub="$SRC/$g"
    [ -e "$sub/.git" ] || die "子模块 $g 在 $SRC 里没有检出，取不到它的文件"
    git -C "$sub" cat-file -e "$sha^{commit}" 2>/dev/null \
        || die "子模块 $g 的本地检出里没有原仓库记录的提交 ${sha:0:9}（先在 $sub 里把它拉下来）"
    sspecs=()
    while IFS="$TAB" read -r sg rel; do
        if [ "$sg" = "$g" ]; then sspecs+=("$rel"); fi
    done <<ITEMS
$sub_items
ITEMS
    rmdir "$work/$g" 2>/dev/null || true
    mkdir -p "$work/$g"
    git -C "$sub" archive "$sha" -- "${sspecs[@]}" | tar -x -C "$work/$g"
    # 它自己里面的子模块不会跟着带过来（导出后只剩空目录），提醒一下
    while IFS="$TAB" read -r _meta np; do
        case "$_meta" in *" commit "*)
            if [ -d "$work/$g/$np" ]; then warn "子模块 $g 里面还有子模块 ${np}，没有带进快照"; fi ;;
        esac
    done <<NESTED
$(git -C "$sub" ls-tree -r "$sha")
NESTED
    inlined="$inlined$g ${sha}
"
done <<SUBLIST
$inline_subs
SUBLIST

# 其余在导出范围内的子模块：按原提交、以子模块的形式带过去。
# （ls-tree 不认排除写法，所以按 .include 的路径前缀自己判断在不在范围内）
in_scope() {
    local p="$1" s
    for s in ${main_excs[@]+"${main_excs[@]}"}; do
        case "$p" in "$s"|"$s"/*) return 1 ;; esac
    done
    for s in ${main_incs[@]+"${main_incs[@]}"}; do
        case "$p" in "$s"|"$s"/*) return 0 ;; esac
    done
    return 1
}
sub_bad=0; subs=""
while IFS="$TAB" read -r sha path; do
    [ -n "$path" ] || continue
    is_inline "$path" && continue
    in_scope "$path" || continue
    key="$(git -C "$SRC" config --blob "$src_sha:.gitmodules" --get-regexp '^submodule\..*\.path$' \
            | awk -v p="$path" '$2==p {sub(/\.path$/,"",$1); print $1}')"
    url="$(git -C "$SRC" config --blob "$src_sha:.gitmodules" --get "$key.url")"
    url="$(printf '%s' "$url" | sed -E 's#^git@([^:]+):#https://\1/#')"
    if ! GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote "$url" >/dev/null 2>&1; then
        warn "子模块 ${path}（${url}）匿名拉不到。三选一：!$path 排除；@$path 把它的文件直接并进快照（或只写里面需要的路径）；把它登记进 repos.txt 公开"
        sub_bad=1; continue
    fi
    rmdir "$work/$path" 2>/dev/null || true
    git -C "$work" config -f .gitmodules "submodule.$path.path" "$path"
    git -C "$work" config -f .gitmodules "submodule.$path.url" "$url"
    subs="$subs$sha $path
"
done <<TREE
$links
TREE
[ "$sub_bad" = 0 ] || die "有子模块拉不到，快照没有提交。"

printf '由 mac_setup 的 local/snapshot.sh 自动生成，勿手改。\n来源提交: %s\n' "$src_sha" > "$work/SNAPSHOT_SOURCE"
[ -z "$inlined" ] || printf '文件直接并进来的子模块（路径 提交）:\n%s' "$inlined" >> "$work/SNAPSHOT_SOURCE"

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
