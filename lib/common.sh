# 目标机公共函数库：被 install.sh / uninstall.sh / 各模块 source。
# 必须兼容 macOS 自带的 bash 3.2（不用关联数组、mapfile 等）。
#
# 记账约定（卸载靠它恢复原状，见 docs/decisions/architecture.md）：
#   清单文件 $MS_MANIFEST 每行「类型<TAB>目标<TAB>附加」，类型有：
#     path     我们创建的文件 / 目录 / 软链接（卸载时删除）
#     backup   原来就有、被我们挪走的东西（目标 = 原路径，附加 = 备份位置；卸载时放回）
#     formula  我们装的 Homebrew formula      cask  我们装的 Homebrew cask
#     brew     Homebrew 本身是我们装的        clt   Xcode 命令行工具是我们装的
#     brewhome Homebrew 的用户配置目录（默认 ~/.homebrew）原来没有（卸载时在最后一条 brew 命令之后删）
#     brewcache 我们下载到 Homebrew 缓存里的安装包（Homebrew 原来就有时才记；卸载软件之后删）
#   原来就有的软件和配置不记账，卸载时不会碰。

MS_HOME="${MS_HOME:-$HOME/.mac_setup}"
MS_MANIFEST="$MS_HOME/manifest.tsv"
MS_BACKUP_DIR="$MS_HOME/backup"
MS_TODO="$MS_HOME/manual-steps.txt"
MS_LOG="$MS_HOME/install.log"

ms_log()  { printf '\033[0;32m[mac_setup]\033[0m %s\n' "$*"; }
ms_warn() { printf '\033[1;33m[mac_setup] 注意:\033[0m %s\n' "$*" >&2; }
ms_die()  { printf '\033[0;31m[mac_setup] 失败:\033[0m %s\n' "$*" >&2; exit 1; }

ms_state_init() {
    mkdir -p "$MS_BACKUP_DIR"
    touch "$MS_MANIFEST" "$MS_TODO"
}

# ms_recorded <类型> <目标>：清单里有没有这一条
ms_recorded() {
    [ -f "$MS_MANIFEST" ] || return 1
    awk -F'\t' -v t="$1" -v v="$2" '$1==t && $2==v {f=1} END{exit !f}' "$MS_MANIFEST"
}

# ms_record <类型> <目标> [附加]：记一条（已有则不重复记）
ms_record() {
    ms_recorded "$1" "$2" && return 0
    printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >> "$MS_MANIFEST"
}

# ms_backup <绝对路径>：动一个路径之前调用。原来就有 → 挪进备份目录并记账。
# 重跑安全：已经是我们创建的、或原件已经备份过的，不再备份（否则会拿我们装的东西盖掉原件的备份）。
ms_backup() {
    local p="$1" dest
    [ -e "$p" ] || [ -L "$p" ] || return 0
    ms_recorded path "$p" && return 0
    ms_recorded backup "$p" && return 0
    dest="$MS_BACKUP_DIR$p"
    mkdir -p "$(dirname "$dest")"
    mv "$p" "$dest"
    ms_record backup "$p" "$dest"
    ms_log "已备份原有的 $p → $dest"
}

# ms_claim <绝对路径>：「我要在这里创建东西」——先备份原有的，再记为我们创建的。
# 模块里凡是要新建 / 覆盖的路径，创建之前都调它。
ms_claim() {
    ms_backup "$1"
    ms_record path "$1"
}

# ms_todo <一句话>：登记一条必须人工做的事（登录、授权等），install.sh 结束时统一列出
ms_todo() {
    grep -Fqx "$*" "$MS_TODO" 2>/dev/null || printf '%s\n' "$*" >> "$MS_TODO"
}

# ---------- Homebrew ----------

ms_brew_load() {
    local b
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$b" ]; then eval "$("$b" shellenv)"; return 0; fi
    done
    return 1
}

# Homebrew 的用户配置目录，取值规则照 bin/brew。brew 用到时才自己建（如 7.x 的信任记录
# trust.json 及其锁文件，`brew uninstall` 就会碰），官方卸载脚本不清它。
ms_brew_cfgdir() {
    if [ -n "${XDG_CONFIG_HOME:-}" ]; then
        printf '%s\n' "$XDG_CONFIG_HOME/homebrew"
    elif [ -n "${HOMEBREW_XDG_CONFIG_HOME:-}" ]; then
        printf '%s\n' "$HOMEBREW_XDG_CONFIG_HOME/homebrew"
    else
        printf '%s\n' "$HOME/.homebrew"
    fi
}

# 没有 Homebrew 就装（顺带装 Xcode 命令行工具），并记账是我们装的
ms_brew_ensure() {
    # 第一次用 brew 之前：用户配置目录原来没有 → 记账（不管 Homebrew 是谁装的，之后冒出来的都算我们的）。
    # 它可能到卸载阶段才被 brew 建出来，所以现在不存在也要记。
    local cfg
    cfg="$(ms_brew_cfgdir)"
    [ -e "$cfg" ] || [ -L "$cfg" ] || ms_record brewhome "$cfg"
    ms_brew_load && return 0
    # 先记账再安装：安装中途被打断时，卸载仍然知道这两样是我们带来的
    local prefix=/opt/homebrew
    [ "$(uname -m)" = arm64 ] || prefix=/usr/local
    [ -d /Library/Developer/CommandLineTools ] || ms_record clt /Library/Developer/CommandLineTools
    ms_record brew "$prefix"
    ms_log "安装 Homebrew（会顺带装 Xcode 命令行工具，需要几分钟）..."
    # 有终端时让它正常提示输入 sudo 密码；没有终端（如经 ssh 演练）时不能交互，
    # 并且不让它读标准输入——那里可能排着调用方后面要执行的命令
    if [ -t 0 ]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
            || ms_die "Homebrew 安装失败"
    else
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null \
            || ms_die "Homebrew 安装失败"
    fi
    ms_brew_load || ms_die "Homebrew 装完后找不到 brew"
}

# Homebrew 的下载缓存：brew install 把安装包（连同依赖的）下载到缓存目录，brew uninstall（含 --zap）不清它。
# Homebrew 是我们装的 → 卸载时整个缓存目录一起没，不用管；它原来就有时，我们下载的安装包要自己清。
# 做法：每次 brew install 前后各列一遍缓存，多出来的条目记账（brewcache），卸载时按清单删。
# 不按软件名去匹配：依赖的安装包叫什么事先不知道，而且对方原来就缓存着的同名安装包不该删。

# ms_brew_cache_list：列出缓存里的安装包条目，每行一个绝对路径
# （顶层和 Cask/ 下的链接、downloads/ 下的文件；brew 自己运转用的数据如 api/、bootsnap/ 不算）
ms_brew_cache_list() {
    local c
    c="$(brew --cache 2>/dev/null)" || return 0
    if [ -z "$c" ] || [ ! -d "$c" ]; then return 0; fi
    {
        find "$c" -mindepth 1 -maxdepth 1 -type l 2>/dev/null || true
        if [ -d "$c/Cask" ]; then find "$c/Cask" -mindepth 1 -maxdepth 1 -type l 2>/dev/null || true; fi
        if [ -d "$c/downloads" ]; then find "$c/downloads" -mindepth 1 -maxdepth 1 -type f 2>/dev/null || true; fi
    } | LC_ALL=C sort
}

# brew install 会读标准输入：调用方的标准输入里若还排着后续命令（一次送多条命令、粘贴多行），
# 会被它全部读走——安装成功，后面的命令却一条不执行、也不报错。所以一律接 /dev/null。
# （需要 sudo 密码时 sudo 自己从终端读，不走标准输入。）

# ms_brew_install <brew install 的参数...>：跑 brew install，并把它新下载进缓存的安装包记账。
# 安装失败也记：下到一半的东西同样是我们带来的。
ms_brew_install() {
    local before="" rc=0 f
    if ! ms_recorded brew /opt/homebrew && ! ms_recorded brew /usr/local; then
        before="$(mktemp "$MS_HOME/brewcache.XXXXXX" 2>/dev/null)" || before=""
        if [ -n "$before" ]; then ms_brew_cache_list > "$before"; fi
    fi
    brew install "$@" </dev/null || rc=$?
    if [ -n "$before" ]; then
        ms_brew_cache_list | LC_ALL=C comm -13 "$before" - | while IFS= read -r f; do
            ms_record brewcache "$f"
        done
        rm -f "$before"
    fi
    return "$rc"
}

# ms_formula <formula>：原来就装了 → 不动、不记账
ms_formula() {
    ms_brew_ensure
    if brew list --formula "$1" >/dev/null 2>&1; then return 0; fi
    ms_log "brew install $1"
    ms_brew_install "$1" || return 1
    ms_record formula "$1"
}

# ms_cask <cask> [应用名.app]：/Applications 里原来就有这个应用 → 不动、不记账
ms_cask() {
    ms_brew_ensure
    if brew list --cask "$1" >/dev/null 2>&1; then return 0; fi
    if [ -n "${2:-}" ] && [ -d "/Applications/$2" ]; then
        ms_log "$2 原来就有，不动"
        return 0
    fi
    ms_log "brew install --cask $1"
    ms_brew_install --cask "$1" || return 1
    ms_record cask "$1"
}

# ---------- 卸载用 ----------

# ms_remove_path <绝对路径>：只删清单里记为我们创建的东西，且限定在已知安全的前缀下
ms_remove_path() {
    local p="$1"
    case "$p" in
        *..*) ms_warn "拒绝删除（路径含 ..）: $p"; return 0 ;;
        "$HOME"/?*|/Applications/?*|/opt/homebrew/?*|/usr/local/?*|/Library/?*) ;;
        *) ms_warn "拒绝删除（不在允许的位置）: $p"; return 0 ;;
    esac
    [ -e "$p" ] || [ -L "$p" ] || return 0
    rm -rf -- "$p" 2>/dev/null || sudo rm -rf -- "$p"
}

# ms_remove_cached <绝对路径>：删一个记为我们下载的缓存条目。只删文件和链接，不删目录。
ms_remove_cached() {
    local p="$1"
    case "$p" in
        ""|[!/]*|*..*) ms_warn "拒绝删除（不是正常的绝对路径）: $p"; return 0 ;;
    esac
    if [ -L "$p" ] || [ -f "$p" ]; then rm -f -- "$p"; fi
}
