#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# 构建云卷 (Cloud Volume) Linux AppImage 打包脚本
#
# 用法:
#   ./scripts/build_appimage.sh [选项]
#
# 选项:
#   --version <x.y.z>    版本号 (默认: 1.0.0)
#   --build-number <num> 构建编号 (默认: 1)
#   --arch <name>        目标架构: amd64|arm64 (默认: 自动检测)
#   --output-dir <path>  产物输出目录 (默认: dist/)
#   --skip-bridge        跳过 Go bridge 编译 (使用已有的 .so)
#   --skip-flutter       跳过 Flutter 编译 (使用已有的 bundle)
#   -h, --help           显示帮助
#
# 环境变量:
#   APPIMAGE_TOOL_VERSION  appimagetool 版本标签 (默认: continuous)
#   BRIDGE_CC              Go bridge 交叉编译用的 C 编译器
#
# 依赖:
#   - Go (CGO_ENABLED=1)
#   - Flutter SDK
#   - curl (下载 appimagetool)
#   - pkg-config, GTK 3 (Flutter Linux 构建所需)
# ─────────────────────────────────────────────────────────────
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="云卷"
ARTIFACT_PREFIX="${ARTIFACT_PREFIX:-yunjuan}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ARCH=""
OUTPUT_DIR=""
SKIP_BRIDGE=false
SKIP_FLUTTER=false
APPIMAGE_TOOL_VERSION="${APPIMAGE_TOOL_VERSION:-continuous}"

usage() {
  cat <<'EOF'
用法: ./scripts/build_appimage.sh [选项]

选项:
  --version <x.y.z>    版本号 (默认: 1.0.0)
  --build-number <num> 构建编号 (默认: 1)
  --arch <name>        目标架构: amd64|arm64 (默认: 自动检测)
  --output-dir <path>  产物输出目录 (默认: dist/)
  --skip-bridge        跳过 Go bridge 编译 (使用已有的 .so)
  --skip-flutter       跳过 Flutter 编译 (使用已有的 bundle)
  -h, --help           显示帮助
EOF
}

fail() {
  printf '错误: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少命令: $1"
}

# 从 PATH 或常见安装位置解析 Go 编译器路径
resolve_go() {
  if command -v go >/dev/null 2>&1; then
    GO_CMD="go"
    return
  fi
  local candidates=(
    /usr/local/go/bin/go
    /usr/lib/go/bin/go
    /snap/go/current/bin/go
    "$HOME/sdk/go/go/bin/go"
    "$HOME/sdk/go/bin/go"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      GO_CMD="$candidate"
      printf '→ Go 编译器: %s\n' "$GO_CMD"
      return
    fi
  done
  fail "找不到 Go 编译器。请安装 Go 1.24+ 或将其加入 PATH。"
}

detect_arch() {
  local detected
  detected="$(uname -m | tr '[:upper:]' '[:lower:]')"
  case "$detected" in
    x86_64|amd64) printf 'amd64\n' ;;
    arm64|aarch64) printf 'arm64\n' ;;
    *) fail "不支持的系统架构: $detected" ;;
  esac
}

# ── 架构名称转换 ────────────────────────────────────────────

go_arch() {
  case "$1" in
    amd64) printf 'amd64\n' ;;
    arm64) printf 'arm64\n' ;;
    *) fail "不支持的 Go 架构: $1" ;;
  esac
}

flutter_target() {
  case "$1" in
    amd64) printf 'linux-x64\n' ;;
    arm64) printf 'linux-arm64\n' ;;
    *) fail "不支持的 Flutter 目标平台: $1" ;;
  esac
}

appimage_arch() {
  case "$1" in
    amd64) printf 'x86_64\n' ;;
    arm64) printf 'aarch64\n' ;;
    *) fail "不支持的 AppImage 架构: $1" ;;
  esac
}

build_bridge() {
  local arch="$1"
  local go_arch_str
  go_arch_str="$(go_arch "$arch")"
  local output_dir="$ROOT_DIR/bin/bridge"
  mkdir -p "$output_dir"

  printf '→ 编译 Go bridge (GOARCH=%s) ...\n' "$go_arch_str"
  if [[ -n "${BRIDGE_CC:-}" ]]; then
    export CC="$BRIDGE_CC"
  fi
  env CGO_ENABLED=1 GOOS=linux GOARCH="$go_arch_str" \
    "$GO_CMD" build -buildmode=c-shared \
    -o "$output_dir/libremote_storage_bridge.so" \
    ./bridge
  printf '✓ Go bridge 编译完成: %s/libremote_storage_bridge.so\n' "$output_dir"
}

build_flutter() {
  local arch="$1"
  local target
  target="$(flutter_target "$arch")"

  printf '→ 编译 Flutter Linux release (%s) ...\n' "$target"
  flutter build linux --release \
    --target-platform "$target" \
    --build-name "$VERSION" \
    --build-number "$BUILD_NUMBER"
  printf '✓ Flutter 编译完成\n'
}

download_appimagetool() {
  local arch="$1"
  local tool_path="$2"
  local tool_arch
  tool_arch="$(appimage_arch "$arch")"

  if [[ -x "$tool_path" ]]; then
    printf '→ appimagetool 已存在，跳过下载\n'
    return
  fi

  printf '→ 下载 appimagetool (%s) ...\n' "$tool_arch"
  curl -fsSL \
    "https://github.com/AppImage/appimagetool/releases/download/${APPIMAGE_TOOL_VERSION}/appimagetool-${tool_arch}.AppImage" \
    -o "$tool_path"
  chmod +x "$tool_path"
  printf '✓ appimagetool 下载完成\n'
}

write_apprun() {
  local apprun_path="$1"
  cat > "$apprun_path" <<'APP_RUN_EOF'
#!/usr/bin/env sh
# 云卷 AppImage 启动脚本
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$HERE/remote_storage" "$@"
APP_RUN_EOF
  chmod +x "$apprun_path"
}

write_desktop_file() {
  local desktop_path="$1"
  cat > "$desktop_path" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=云卷
Comment=云端卷宗管理器 - S3 兼容对象存储桌面客户端
Exec=remote_storage
Icon=yunjuan
Terminal=false
Categories=Network;FileTools;Utility;
StartupNotify=true
DESKTOP_EOF
}

# ── 主流程 ──────────────────────────────────────────────────

main() {
  # 参数解析
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        VERSION="${2:-}"; shift 2 ;;
      --build-number)
        BUILD_NUMBER="${2:-}"; shift 2 ;;
      --arch)
        ARCH="${2:-}"; shift 2 ;;
      --output-dir)
        OUTPUT_DIR="${2:-}"; shift 2 ;;
      --skip-bridge)
        SKIP_BRIDGE=true; shift ;;
      --skip-flutter)
        SKIP_FLUTTER=true; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        fail "未知参数: $1 (使用 -h 查看帮助)" ;;
    esac
  done

  ARCH="${ARCH:-$(detect_arch)}"
  OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
  mkdir -p "$OUTPUT_DIR"

  printf '═══════════════════════════════════════════════\n'
  printf '  云卷 AppImage 构建\n'
  printf '  版本: %s (build %s)\n' "$VERSION" "$BUILD_NUMBER"
  printf '  架构: %s\n' "$ARCH"
  printf '  输出: %s\n' "$OUTPUT_DIR"
  printf '═══════════════════════════════════════════════\n\n'

  # 步骤 1: 编译 Go bridge
  if [[ "$SKIP_BRIDGE" == true ]]; then
    printf '→ 跳过 Go bridge 编译\n'
  else
    resolve_go
    build_bridge "$ARCH"
  fi

  # 步骤 2: 编译 Flutter Linux release
  if [[ "$SKIP_FLUTTER" == true ]]; then
    printf '→ 跳过 Flutter 编译\n'
  else
    require_cmd flutter
    build_flutter "$ARCH"
  fi

  # 步骤 3: 组装 AppDir
  printf '→ 组装 AppDir ...\n'
  local build_arch bundle_dir bridge_so temp_dir app_dir
  build_arch="$(linux_build_arch "$ARCH")"
  bundle_dir="$ROOT_DIR/build/linux/$build_arch/release/bundle"
  bridge_so="$ROOT_DIR/bin/bridge/libremote_storage_bridge.so"

  [[ -d "$bundle_dir" ]] || fail "Flutter bundle 目录不存在: $bundle_dir\n请先执行 Flutter 编译 (或使用 --skip-flutter 配合已有构建产物)"
  [[ -f "$bridge_so" ]] || fail "Go bridge 不存在: $bridge_so\n请先执行 bridge 编译 (或使用 --skip-bridge 配合已有构建产物)"

  temp_dir="$(mktemp -d)"
  app_dir="$temp_dir/${APP_NAME}.AppDir"
  mkdir -p "$app_dir"

  # 复制 Flutter bundle
  cp -R "$bundle_dir"/. "$app_dir/"

  # 复制 Go bridge .so
  cp "$bridge_so" "$app_dir/libremote_storage_bridge.so"

  # 写入 AppRun
  write_apprun "$app_dir/AppRun"

  # 写入 .desktop 文件
  write_desktop_file "$app_dir/yunjuan.desktop"

  # 复制应用图标 (从 macOS 图标资源中取 512x512)
  local icon_src="$ROOT_DIR/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png"
  if [[ -f "$icon_src" ]]; then
    cp "$icon_src" "$app_dir/yunjuan.png"
  else
    fail "应用图标未找到: $icon_src"
  fi

  printf '✓ AppDir 组装完成: %s\n' "$app_dir"

  # 步骤 4: 下载 appimagetool 并打包 AppImage
  local tool_path appimage_arch_str appimage_path
  tool_path="$temp_dir/appimagetool.AppImage"
  download_appimagetool "$ARCH" "$tool_path"

  appimage_arch_str="$(appimage_arch "$ARCH")"
  appimage_path="$OUTPUT_DIR/$ARTIFACT_PREFIX-linux-$ARCH.AppImage"
  mkdir -p "$(dirname "$appimage_path")"

  printf '→ 打包 AppImage ...\n'
  APPIMAGE_EXTRACT_AND_RUN=1 ARCH="$appimage_arch_str" \
    "$tool_path" "$app_dir" "$appimage_path" >/dev/null

  # 清理临时目录
  rm -rf "$temp_dir"

  printf '\n✓ AppImage 构建完成!\n'
  printf '  产物: %s\n' "$appimage_path"
  printf '  大小: %s\n' "$(du -h "$appimage_path" | awk '{print $1}')"
}

# 辅助: linux build 子目录名
linux_build_arch() {
  case "$1" in
    amd64) printf 'x64\n' ;;
    arm64) printf 'arm64\n' ;;
    *) fail "不支持的 Linux 架构: $1" ;;
  esac
}

main "$@"
