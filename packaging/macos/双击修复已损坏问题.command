#!/bin/bash
# Removes Gatekeeper quarantine flags from the installed app bundle.
set -euo pipefail

APP_PATH="/Applications/云卷.app"
if [[ ! -d "$APP_PATH" ]]; then
  osascript <<'APPLESCRIPT'
display dialog "未在 /Applications 找到 云卷.app。\n\n请先将云卷拖到 Applications 文件夹后，再双击运行此脚本。" buttons {"好"} default button "好" with icon caution
APPLESCRIPT
  exit 1
fi

xattr -dr com.apple.quarantine "$APP_PATH"
osascript <<'APPLESCRIPT'
display dialog "已完成修复。\n\n如果云卷已经在 Applications 中，现在可以重新打开它。" buttons {"好"} default button "好" with icon note
APPLESCRIPT
