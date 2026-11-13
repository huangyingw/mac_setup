# 模块约定

每个域一个目录 `modules/NN-名字/`，`install.sh`（入口）按目录名顺序逐个执行。

| 文件 | 何时运行 | 要求 |
|---|---|---|
| `install.sh` | 安装时 | 必须有。**可重复运行**（重跑不出错、不重复备份） |
| `uninstall.sh` | 恢复原状时（反序） | 可选。只放清单管不到的清理：退出登录、删应用自己写的设置和缓存等 |

模块以独立的 bash 进程运行，开头固定两行：

```bash
set -euo pipefail
. "$MS_SRC/lib/common.sh"
```

可用的环境变量：`MS_SRC`（本仓库在目标机上的位置，`~/.mac_setup/src`）、`MS_HOME`（状态目录 `~/.mac_setup`）。

## 必须遵守

1. **兼容 macOS 自带的 bash 3.2**，只用系统自带命令和本模块自己装的东西。
2. **动任何已有路径之前先 `ms_claim <绝对路径>`**（原有的会被挪进备份、并记为我们创建的），然后再创建。
   只想备份、不创建就用 `ms_backup`。直接覆盖对方已有的文件是缺陷。
3. **共用的上级目录用 `ms_claim_dir <目录>...`，不要 `ms_claim`、不要记成 `path`**：`~/.local`、`~/.local/share`、`~/.config`、`~/.cache`、`~/Library/LaunchAgents` 这类不属于哪一个程序的目录，原来没有才建、才记账（记为 `newdir`），恢复原状时由 `uninstall.sh` 统一处理——**空了才删**，别人后放进去的东西不碰。模块不要自己定义同类函数，`uninstall.sh` 里也不要自己处理 `newdir`。
   相应地，自己装的工具运行时会往这些目录里写的位置（缓存、状态文件），用 `ms_own_if_absent <路径>...` 记上（原来没有才记，不创建），否则上级目录空不下来、会留在对方机器上。
4. **装软件走 `ms_formula` / `ms_cask`**：它们会跳过对方原来就有的，并把我们装的记账。
   不经它们装的东西（下载的模型、`npm -g`、`curl | sh` 安装器等）自己用 `ms_claim` 把落地路径记上。
5. **会读标准输入的命令接 `</dev/null`**（各种安装器常见）：否则它会把调用方排在后面的命令读走，后面的悄悄不执行。`ms_formula` / `ms_cask` 已经处理；没有终端时整个安装的标准输入本来就是空的，但在终端里运行时要靠各模块自己堵。
6. **不能自动完成的事用 `ms_todo "<一句话>"` 登记**（账号登录、系统权限授权等），不要悄悄跳过。
7. **不依赖参考机**：不能假设有人从别的机器 ssh 进来配合；需要的内容只能从公开的 GitHub 仓库或官方下载地址取。
8. 内容来自别的仓库时，用 `https://` 匿名拉取，仓库必须登记在 `repos.txt`。

公共函数见 `lib/common.sh`，记账与卸载的设计见 `docs/decisions/architecture.md`。框架的回归测试在 `tests/`（在临时家目录里跑，不碰真实环境）：`bash tests/shared_dirs.sh`。

## 单独调试一个模块

```bash
# 参考机上：提交并推送后
ssh mba.local 'MS_REFRESH=1 bash ~/.mac_setup/src/install.sh <模块名>'   # 重新下载仓库并只跑这一个模块
```

## 演练机是几个分支共用的

`mba` 同时被各域分支拿来测试，Homebrew 和 Xcode 命令行工具只有一份。**记着「这两样是我们装的」的是默认状态目录 `~/.mac_setup` 里的清单**：用默认状态目录跑 `uninstall.sh`，会把 Homebrew 连同经它装的全部软件、以及命令行工具一起卸掉，别的分支正在用的测试环境随之失效（重装要十几分钟）。

测自己模块的「安装 → 卸载还原」时，用自己的状态目录，清单里就只有自己这次装的东西，卸载不会碰 Homebrew：

```bash
ssh mba.local 'export MS_HOME=$HOME/.mac_setup_<分支名>; bash -c "$(curl -fsSL https://raw.githubusercontent.com/huangyingw/mac_setup/integration/install.sh)" _ <模块名>'
ssh mba.local 'MS_HOME=$HOME/.mac_setup_<分支名> bash ~/.mac_setup_<分支名>/src/uninstall.sh'
```

- 状态目录必须以 `~/.mac_setup` 开头（卸载结尾只肯删这样的目录）；
- 卸载会依次跑 `modules/` 下**每个**模块的 `uninstall.sh`，所以模块的卸载脚本只能动自己记过账的东西，清单里没有就什么都不做；
- 用默认状态目录的整套卸载（含卸 Homebrew）只在 `integration` 做整体演练时跑。
