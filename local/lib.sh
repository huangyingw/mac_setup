# 参考机脚本（publish / unpublish / snapshot）的公共部分。
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOS_FILE="$ROOT/repos.txt"

# 这几个仓库无论清单怎么写都拒绝公开
NEVER_PUBLIC="huangyingw/loadrc huangyingw/ssh huangyingw/keys"

# 光看文件名就不该出现在公开仓库里的东西（gitleaks 按内容查，这里按名字补一道）
SENSITIVE_NAMES='(^|/)(id_(rsa|dsa|ecdsa|ed25519)|ssh_host_[a-z0-9]+_key|identity\.secret|\.env|\.credentials\.json|auth\.json|[^/]*\.(pem|p12|pfx|keystore))$'

info() { printf '\033[0;32m[publish]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[publish] 注意:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[publish] 失败:\033[0m %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "缺少命令 $1"; }

# 逐行输出「仓库 方式 第三列」，去掉注释和空行
each_repo() { sed -e 's/#.*//' "$REPOS_FILE" | awk 'NF>=3 {print $1, $2, $3}'; }

expand_path() {
    case "$1" in
        .)     printf '%s\n' "$ROOT" ;;
        "~"/*) printf '%s\n' "$HOME/${1#\~/}" ;;
        *)     printf '%s\n' "$1" ;;
    esac
}

visibility() { gh repo view "$1" --json visibility -q .visibility 2>/dev/null; }

guard_slug() {
    local s
    for s in $NEVER_PUBLIC; do
        [ "$1" = "$s" ] && die "$1 在「永不公开」名单里，不能写进 repos.txt"
    done
    return 0
}

snapshot_workdir() { printf '%s\n' "$HOME/.cache/mac_setup/snapshots/$1"; }

# scan_history <本地检出>：先与 GitHub 对齐，再扫描 GitHub 上有的全部历史（内容 + 文件名）
scan_history() {
    local path="$1" names
    git -C "$path" fetch --quiet --tags origin || die "$path: git fetch 失败"
    if [ -z "$(git -C "$path" for-each-ref refs/remotes/origin | head -1)" ]; then
        info "  （远程还没有任何提交，跳过）"; return 0
    fi
    gitleaks git "$path" --log-opts="--remotes=origin --tags" --redact --no-banner --log-level warn \
        || { warn "$path: 提交历史里发现疑似密钥（上面是 gitleaks 的输出）"; return 1; }
    names="$(git -C "$path" log --remotes=origin --tags --name-only --format= | sort -u | grep -E "$SENSITIVE_NAMES" || true)"
    if [ -n "$names" ]; then
        warn "$path: 提交历史里出现过这些敏感文件名："
        printf '    %s\n' $names >&2
        return 1
    fi
}

# scan_tree <目录>：扫描一个目录当前的文件（内容 + 文件名），不看 .git
scan_tree() {
    local dir="$1" names
    gitleaks dir "$dir" --redact --no-banner --log-level warn \
        || { warn "$dir: 文件内容里发现疑似密钥（上面是 gitleaks 的输出）"; return 1; }
    names="$(cd "$dir" && find . -path ./.git -prune -o -type f -print | sed 's|^\./||' | grep -E "$SENSITIVE_NAMES" || true)"
    if [ -n "$names" ]; then
        warn "$dir: 有这些敏感文件名："
        printf '    %s\n' $names >&2
        return 1
    fi
}
