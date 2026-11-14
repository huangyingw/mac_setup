# 远程图形连接（NoMachine）怎么装

记录日期：2026-11-13。对应 `modules/50-nomachine`。

## 1. 参考机现状

| 部分 | 参考机 `studio` |
|---|---|
| 版本 | 9.10.3（当初经 Homebrew cask `nomachine` 装的 9.8.2_1，之后它自己自动更新上来） |
| 服务端配置 | `/Applications/NoMachine.app/Contents/Frameworks/etc/server.cfg`、`node.cfg`，与同目录安装时留下的 `.backup` **完全相同**，即全部用默认值：NX 协议、端口 4000、用这台机器的系统账号和密码登录 |
| 系统授权 | 「屏幕与系统录音」「辅助功能」都给了 `com.nomachine.nxdock`（界面上显示为 NoMachine） |
| 家目录里的东西 | `~/.nx`（连接记录、日志）、`~/Documents/NoMachine`（录像、收到的文件）、`~/Library/Preferences/com.nomachine.nxdock.plist` |

所以「配成和参考机一样」就是：**装好、不改配置**。

## 2. 免费版没了：只能装 10.x Personal Edition

调查时发现（2026-11-13）：

- NoMachine 从 10 版起**不再有免费的服务端**。官方 FAQ 原话：以前的版本里提供过免费的服务端版本，「this product has been discontinued」；要用 10 版的，个人或商业用途都得用入门级的 Personal Edition，或者继续用以前装的 9 版。
- 官网下载页只剩 10.2.3「NoMachine Personal Edition for Mac」（`https://download.nomachine.com/download/?id=117&platform=mac`）。9.x 的安装包地址都会被重定向回官网首页，**官方渠道已经下不到 9.x**。
- Homebrew 的 cask `nomachine` 还指着 9.8.2_1，下载到的其实是官网首页，校验和对不上，**装不上**。
- 10.x 服务端**没激活不接受任何连接**。激活办法：订阅（Personal Edition 每台机器每年 24.50 美元），或 14 天试用许可。试用许可要在 nomachine.com 登录账号，在 User Area → Software → Evaluations 里生成，**只能在网页上做**；生成后在这台机器上用 `sudo /etc/NX/nxserver --subscriptionset <许可码或 server.lic 路径>` 装上。许可要联网校验（启动时和之后每 48 小时一次，连不上服务器还能再用 48 小时）。
- 客户端（NoMachine 的连接端）仍然免费。

因此模块的做法是：

1. 从官网下载页取当前版本的 dmg 地址和页面上写的 MD5；
2. 下载后核对 MD5，再核对 pkg 的签名必须是 `Developer ID Installer: NoMachine S.a.r.l. (493C5JZAGR)`、并经苹果认可（`spctl -a -t install`）——签名才是真正的把关，MD5 只防下载出错；
3. 用系统的 `installer` 装（不经 Homebrew，清单里记 `nm-pkg`，由本模块的 `uninstall.sh` 负责卸）；
4. 不改任何配置；
5. 许可没激活 → 结尾列为人工事项。

不选的办法：从第三方镜像下 9.x（不是官方渠道，违反 `modules/README.md` 第 7 条，也没法保证安装包没被动过）。

## 3. 人工事项（脚本结尾列出）

1. 激活许可（见上节）；
2. 系统设置 → 隐私与安全性 → 「屏幕与系统录音」和「辅助功能」打开 NoMachine。不开的话连上去只看得到桌面背景，鼠标键盘不起作用。这两项苹果不让脚本授予，**必须在这台机器跟前做**；
3. 在别的机器上用 NoMachine 客户端连 `<电脑名>.local:4000`，用这台机器的账号和登录密码登录。

防火墙开着（普通模式）时脚本自动放行 `nxd` 并记账；设成「阻止所有传入连接」时只列为人工事项，不替机主改。

## 4. 恢复原状

安装包改动的系统位置：`/Applications/NoMachine.app`、`/Library/Application Support/NoMachine`、`/Library/LaunchDaemons` 与 `/Library/LaunchAgents` 下的 `com.nomachine.*`、`/etc/NX`、`/etc/pam.d/nx`、`/Library/Audio/Plug-Ins/HAL/NMAudio*.driver`、隐藏的系统用户和组 `nx`（并被加进 `com.apple.access_ssh` 组和登录窗口的隐藏用户列表）、安装记录 `com.nomachine.*`。

官方卸载流程是「删掉应用 → 守护进程 `com.nomachine.uninstall` 发现后跑 `nxuninstall.sh`」，新系统上删系统用户那一步还交给一个要输密码的「NoMachine Uninstall」窗口。`brew uninstall --zap` 会先停掉那个守护进程再删应用，官方脚本就不跑了，上面这些大都会留下。所以 `uninstall.sh`：

1. 先停掉两个官方卸载触发器（免得后台另跑一份、或弹出要密码的窗口）和本用户会话里的 NoMachine 服务；
2. 删应用，同步跑官方 `nxuninstall.sh`（它的退出码不可信，按日志里的错误行判断）；
3. 自己补上官方交给图形界面的部分：用 `dscl` 删系统用户和组 `nx`（不用 `sysadminctl -deleteUser`——它会在 `/Library/Preferences/com.apple.preferences.accounts.plist` 留一条「删过的用户」记录）、从 `com.apple.access_ssh` 和隐藏用户列表里摘掉（列表原来没有就整项删掉）、删支持目录、`pkgutil --forget`；
4. 别的程序替它记下的条目：辅助功能提示记录、音频服务记下的两块虚拟声卡、`~/.qt`。原来没有这些文件 → 安装时记为我们的，整个删；原来就有 → 只摘 NoMachine 的条目；
5. 收回给它的系统授权（`tccutil reset All com.nomachine.nxdock`）。

家目录里的 `~/.nx`、`~/Documents/NoMachine`、设置文件在安装前就认领了（原有的先备份），恢复原状时直接删掉、不进废纸篓。

## 5. 演练结果（mba，2026-11-13）

- 安装 → 服务在 4000 端口监听，从参考机能连到该端口；未激活时 `nxserver --subscription` 报「No subscription found」。
- 安装 → 恢复原状，前后对比系统目录、用户和组、登录窗口设置、launchd 服务、家目录：除系统自己的接力服务（`useractivityd`、`studentd`）随时间写的文件外，没有多出来的东西。
- 偶发：官方 postinstall 启动服务时调用的 `system_profiler` 卡了约 10 分钟后自己恢复（单独跑 `system_profiler` 很快），安装提示里写明了。

## 6. 待用户决定

- 要不要用 NoMachine（要账号 + 试用许可或订阅），还是换不要许可的办法（例如 macOS 自带的「屏幕共享」：不用装东西，用 `vnc://` 连；或开源的 RustDesk）；
- 真实面试时要不要默认装：它对外开放 4000 端口、用系统账号密码登录，是对外的远程访问服务，装在别人的电脑上有安全和合规风险。
