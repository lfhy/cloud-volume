#!/usr/bin/env bash
#
# 一键运行脚本 — 构建 Go bridge + 启动 Flutter 桌面应用
#
# 用法：
#   ./scripts/run.sh               # 自动检测平台并运行
#   ./scripts/run.sh --release     # 以 release 模式构建并运行
#
# 注意：请始终从项目根目录执行此脚本。
#
set -euo pipefail

# ── 定位项目根目录 ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "  项目根目录: $PROJECT_ROOT"

RELEASE_MODE=false
if [[ "${1:-}" == "--release" ]]; then
  RELEASE_MODE=true
fi

OS_NAME="$(uname -s)"
case "$OS_NAME" in
  Darwin)  PLATFORM="macos"  ;;
  Linux)   PLATFORM="linux"  ;;
  *)       echo "❌ 不支持的操作系统: $OS_NAME"; exit 1 ;;
esac

echo "============================================"
echo "  云卷 / Cloud Volume — 一键启动"
echo "  平台: $PLATFORM"
echo "  模式: $([ "$RELEASE_MODE" = true ] && echo 'release' || echo 'debug')"
echo "============================================"

# ── 1. 构建 Go bridge ──────────────────────────────────────────
echo ""
echo "📦 构建 Go bridge ..."

# 设置国内可访问的 Go 模块代理（proxy.golang.org 在某些网络环境下不可达）
export GOPROXY=https://goproxy.cn,direct

mkdir -p bin/bridge

case "$PLATFORM" in
  macos)
    go build -buildmode=c-shared -o bin/bridge/libremote_storage_bridge.dylib ./bridge
    ;;
  linux)
    go build -buildmode=c-shared -o bin/bridge/libremote_storage_bridge.so ./bridge
    ;;
esac

echo "✅ Go bridge 构建完成"

# ── 2. 验证必要工具 ────────────────────────────────────────────
echo ""
echo "🔍 检查 Flutter 环境 ..."

if ! command -v flutter &>/dev/null; then
  echo "❌ 未找到 flutter 命令，请确保 Flutter SDK 已安装并加入 PATH"
  exit 1
fi

echo "   $(flutter --version 2>&1 | head -1)"

# ── 3. 获取可用设备 ────────────────────────────────────────────
echo ""
echo "🖥️  检测可用设备 ..."
DEVICE_ID=""

case "$PLATFORM" in
  linux)
    DEVICE_ID="linux"
    ;;
  macos)
    DEVICE_ID="macos"
    # 如果有多个设备，提示用户选择
    DEVICES=$(flutter devices 2>&1 | grep -E 'macos|linux' || true)
    if [ -z "$DEVICES" ]; then
      echo "⚠️  未检测到桌面设备，将使用默认设备"
    fi
    ;;
esac

# ── 4. 启动 Flutter ────────────────────────────────────────────
echo ""
echo "🚀 启动 Flutter 应用 ..."

FLUTTER_ARGS=("run" "-d" "$DEVICE_ID")
if [ "$RELEASE_MODE" = true ]; then
  FLUTTER_ARGS+=("--release")
fi

if [ "$PLATFORM" = "macos" ]; then
  DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
    flutter "${FLUTTER_ARGS[@]}"
else
  flutter "${FLUTTER_ARGS[@]}"
fi
