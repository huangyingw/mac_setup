#!/bin/bash
# 基础工具：Homebrew、git、nvim、iTerm2、Chrome。只负责「装上」，各自的配置归对应模块。
set -euo pipefail
. "$MS_SRC/lib/common.sh"

ms_brew_ensure
ms_formula git
ms_formula neovim
ms_cask iterm2 iTerm.app
ms_cask google-chrome "Google Chrome.app"

ms_todo "Chrome：打开后登录你的 Google 账号"
