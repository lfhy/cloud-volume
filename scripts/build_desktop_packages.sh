#!/usr/bin/env bash
set -euo pipefail

# Build tagged desktop release artifacts for the current native host and stage
# the Go bridge next to each packaged app before publishing.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-云卷}"
ARTIFACT_PREFIX="${ARTIFACT_PREFIX:-yunjuan}"
PLATFORM=""
ARCH=""
VERSION=""
BUILD_NUMBER="1"
OUTPUT_DIR="$ROOT_DIR/dist/release"
MACOS_MIN_VERSION="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
APPIMAGE_TOOL_VERSION="${APPIMAGE_TOOL_VERSION:-continuous}"

usage() {
  cat <<'EOF'
Usage: ./scripts/build_desktop_packages.sh --platform <windows|macos|linux> --arch <name> --version <x.y.z> [options]

Options:
  --platform <name>        Native host platform to package
  --arch <name>            Artifact architecture suffix, such as amd64, arm64, or universal
  --version <x.y.z>        Release version passed to flutter build
  --build-number <num>     Build number passed to flutter build
  --output-dir <path>      Output directory for packaged artifacts
  -h, --help               Show this help
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"
}

resolve_output_dir() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$ROOT_DIR/$1" ;;
  esac
}

detect_arch() {
  local detected
  detected="$(uname -m | tr '[:upper:]' '[:lower:]')"
  case "$detected" in
    x86_64|amd64) printf 'amd64\n' ;;
    arm64|aarch64) printf 'arm64\n' ;;
    *) printf '%s\n' "$detected" ;;
  esac
}

windows_build_arch() {
  case "$1" in
    amd64|x64) printf 'x64\n' ;;
    arm64) printf 'arm64\n' ;;
    *) fail "Unsupported Windows architecture: $1" ;;
  esac
}

linux_flutter_target() {
  case "$1" in
    amd64) printf 'linux-x64\n' ;;
    arm64) printf 'linux-arm64\n' ;;
    *) fail "Unsupported Linux architecture: $1" ;;
  esac
}

linux_build_arch() {
  case "$1" in
    amd64) printf 'x64\n' ;;
    arm64) printf 'arm64\n' ;;
    *) fail "Unsupported Linux architecture: $1" ;;
  esac
}

linux_go_arch() {
  case "$1" in
    amd64) printf 'amd64\n' ;;
    arm64) printf 'arm64\n' ;;
    *) fail "Unsupported Linux Go architecture: $1" ;;
  esac
}

macos_go_arch() {
  case "$1" in
    amd64) printf 'amd64\n' ;;
    arm64) printf 'arm64\n' ;;
    *) fail "Unsupported macOS bridge architecture: $1" ;;
  esac
}

macos_clang_arch() {
  case "$1" in
    amd64) printf 'x86_64\n' ;;
    arm64) printf 'arm64\n' ;;
    *) fail "Unsupported macOS clang architecture: $1" ;;
  esac
}

macos_excluded_archs() {
  case "$1" in
    amd64) printf 'arm64\n' ;;
    arm64) printf 'x86_64\n' ;;
    universal) printf '\n' ;;
    *) fail "Unsupported macOS application architecture: $1" ;;
  esac
}

linux_appimage_arch() {
  case "$1" in
    amd64) printf 'x86_64\n' ;;
    arm64) printf 'aarch64\n' ;;
    *) fail "Unsupported AppImage architecture: $1" ;;
  esac
}

to_windows_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
    return
  fi
  printf '%s' "$1"
}

windows_release_dir() {
  local build_arch="$1"
  printf '%s/build/windows/%s/runner/Release\n' "$ROOT_DIR" "$build_arch"
}

linux_bundle_dir() {
  local build_arch="$1"
  printf '%s/build/linux/%s/release/bundle\n' "$ROOT_DIR" "$build_arch"
}

macos_app_bundle_path() {
  printf '%s/build/macos/Build/Products/Release/%s.app\n' "$ROOT_DIR" "$APP_NAME"
}

ensure_clean_dir() {
  rm -rf "$1"
  mkdir -p "$1"
}

macos_bridge_flags() {
  local arch="$1"
  local clang_arch
  clang_arch="$(macos_clang_arch "$arch")"
  printf '%s' "-arch ${clang_arch} -mmacosx-version-min=${MACOS_MIN_VERSION}"
}

build_macos_bridge() {
  local arch="$1"
  local output_path="$2"
  local go_arch
  go_arch="$(macos_go_arch "$arch")"
  env \
    CGO_ENABLED=1 \
    GOOS=darwin \
    GOARCH="$go_arch" \
    CC=clang \
    CXX=clang++ \
    CGO_CFLAGS="$(macos_bridge_flags "$arch")" \
    CGO_CXXFLAGS="$(macos_bridge_flags "$arch")" \
    CGO_LDFLAGS="$(macos_bridge_flags "$arch")" \
    go build -buildmode=c-shared -o "$output_path" ./bridge
}

build_macos_flutter() {
  local arch="$1"
  local excluded
  excluded="$(macos_excluded_archs "$arch")"
  rm -rf "$ROOT_DIR/build/macos"
  if [[ -n "$excluded" ]]; then
    FLUTTER_XCODE_EXCLUDED_ARCHS="$excluded" \
      flutter build macos --release \
      --dart-define APP_VERSION_LABEL=$VERSION \
      --build-name "$VERSION" \
      --build-number "$BUILD_NUMBER"
    return
  fi

  flutter build macos --release \
    --dart-define APP_VERSION_LABEL=$VERSION \
    --build-name "$VERSION" \
    --build-number "$BUILD_NUMBER"
}

package_macos_zip() {
  local app_bundle="$1"
  local archive_path="$2"
  rm -f "$archive_path"
  (
    cd "$(dirname "$app_bundle")"
    ditto -c -k --sequesterRsrc --keepParent "$(basename "$app_bundle")" "$(basename "$archive_path")"
    mv "$(basename "$archive_path")" "$archive_path"
  )
}

package_macos_dmg() {
  local app_bundle="$1"
  local dmg_path="$2"
  local stage_dir fix_script
  stage_dir="$(mktemp -d)"
  fix_script="$ROOT_DIR/packaging/macos/双击修复已损坏问题.command"
  ditto "$app_bundle" "$stage_dir/$(basename "$app_bundle")"
  [[ -f "$fix_script" ]] || fail "Missing macOS quarantine helper: $fix_script"
  cp "$fix_script" "$stage_dir/$(basename "$fix_script")"
  chmod +x "$stage_dir/$(basename "$fix_script")"
  ln -s /Applications "$stage_dir/Applications"
  rm -f "$dmg_path"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$stage_dir" \
    -ov \
    -format UDZO \
    "$dmg_path" >/dev/null
  rm -rf "$stage_dir"
}

package_linux_tarball() {
  local bundle_dir="$1"
  local archive_path="$2"
  local root_name="$ARTIFACT_PREFIX-linux-$ARCH"
  local stage_dir
  stage_dir="$(mktemp -d)"
  mkdir -p "$stage_dir/$root_name"
  cp -R "$bundle_dir"/. "$stage_dir/$root_name/"
  rm -f "$archive_path"
  tar -C "$stage_dir" -czf "$archive_path" "$root_name"
  rm -rf "$stage_dir"
}

build_macos() {
  require_cmd flutter
  require_cmd go
  require_cmd ditto
  require_cmd hdiutil
  require_cmd lipo
  mkdir -p "$ROOT_DIR/bin/bridge" "$OUTPUT_DIR"

  local app_bundle bridge_path zip_path dmg_path
  local temp_dir staged_app
  temp_dir="$(mktemp -d)"

  build_macos_flutter "$ARCH"
  app_bundle="$(macos_app_bundle_path)"
  [[ -d "$app_bundle" ]] || fail "macOS app bundle not found: $app_bundle"

  staged_app="$temp_dir/$APP_NAME.app"
  ditto "$app_bundle" "$staged_app"

  bridge_path="$staged_app/Contents/Frameworks/libremote_storage_bridge.dylib"
  mkdir -p "$(dirname "$bridge_path")"
  if [[ "$ARCH" == "universal" ]]; then
    local arm_bridge amd_bridge
    arm_bridge="$temp_dir/libremote_storage_bridge.arm64.dylib"
    amd_bridge="$temp_dir/libremote_storage_bridge.amd64.dylib"
    build_macos_bridge arm64 "$arm_bridge"
    build_macos_bridge amd64 "$amd_bridge"
    lipo -create -output "$bridge_path" "$arm_bridge" "$amd_bridge"
  else
    build_macos_bridge "$ARCH" "$bridge_path"
  fi

  zip_path="$OUTPUT_DIR/$ARTIFACT_PREFIX-macos-$ARCH.zip"
  dmg_path="$OUTPUT_DIR/$ARTIFACT_PREFIX-macos-$ARCH.dmg"
  package_macos_zip "$staged_app" "$zip_path"
  package_macos_dmg "$staged_app" "$dmg_path"
  rm -rf "$temp_dir"
}

build_windows_installer() {
  local release_dir="$1"
  local iscc_path="${INNO_SETUP_COMPILER:-}"
  if [[ -z "$iscc_path" ]]; then
    local candidates=(
      "/c/Program Files (x86)/Inno Setup 6/ISCC.exe"
      "/c/Program Files/Inno Setup 6/ISCC.exe"
    )
    local candidate
    for candidate in "${candidates[@]}"; do
      if [[ -f "$candidate" ]]; then
        iscc_path="$candidate"
        break
      fi
    done
  fi
  [[ -n "$iscc_path" ]] || fail "Inno Setup compiler not found"

  local source_dir_win output_dir_win compiler_win
  local installer_base installer_arch
  source_dir_win="$(to_windows_path "$release_dir")"
  output_dir_win="$(to_windows_path "$OUTPUT_DIR")"
  compiler_win="$(to_windows_path "$iscc_path")"
  installer_base="$ARTIFACT_PREFIX-windows-$ARCH-installer"
  installer_arch="x64compatible"
  if [[ "$ARCH" == "arm64" ]]; then
    installer_arch="arm64"
  fi
  local sign_tool sign_pfx sign_password sign_timestamp sign_subject
  sign_tool="${WINDOWS_SIGNTOOL_PATH:-}"
  sign_pfx="${WINDOWS_SIGN_PFX_PATH:-}"
  sign_password="${WINDOWS_SIGN_PFX_PASSWORD:-}"
  sign_timestamp="${WINDOWS_SIGN_TIMESTAMP_URL:-http://timestamp.digicert.com}"
  sign_subject="${WINDOWS_SIGN_SUBJECT:-}"

  powershell.exe -NoProfile -Command \
    "& '$compiler_win' /Qp \
      /DAppName='$APP_NAME' \
      /DAppVersion='$VERSION' \
      /DAppPublisher='云卷' \
      /DAppInstallDirName='Cloud Volume' \
      /DSourceDir='$source_dir_win' \
      /DOutputDir='$output_dir_win' \
      /DOutputBaseFilename='$installer_base' \
      /DArchitecturesAllowed='$installer_arch' \
      /DArchitecturesInstallIn64BitMode='$installer_arch' \
      /DSignTool='$sign_tool' \
      /DSignPfxPath='$(to_windows_path "$sign_pfx")' \
      /DSignPfxPassword='$sign_password' \
      /DSignTimestampUrl='$sign_timestamp' \
      /DSignSubject='$sign_subject' \
      '$(to_windows_path "$ROOT_DIR/scripts/windows_installer.iss")'" >/dev/null
}

build_windows() {
  require_cmd flutter
  require_cmd go
  require_cmd powershell.exe
  mkdir -p "$ROOT_DIR/bin/bridge" "$OUTPUT_DIR"
  (
    cd "$ROOT_DIR"
    if [[ -n "${BRIDGE_CC:-}" ]]; then
      export CC="$BRIDGE_CC"
    fi
    go build -buildmode=c-shared -o bin/bridge/remote_storage_bridge.dll ./bridge
    flutter build windows --release \
      --dart-define APP_VERSION_LABEL=$VERSION \
      --build-name "$VERSION" \
      --build-number "$BUILD_NUMBER"
  )

  local build_arch release_dir bridge_dll zip_path
  build_arch="$(windows_build_arch "$ARCH")"
  release_dir="$(windows_release_dir "$build_arch")"
  bridge_dll="$ROOT_DIR/bin/bridge/remote_storage_bridge.dll"
  zip_path="$OUTPUT_DIR/$ARTIFACT_PREFIX-windows-$ARCH.zip"
  [[ -d "$release_dir" ]] || fail "Windows release directory not found: $release_dir"
  [[ -f "$bridge_dll" ]] || fail "Windows bridge was not built: $bridge_dll"

  cp "$bridge_dll" "$release_dir/remote_storage_bridge.dll"
  local release_dir_win zip_path_win
  release_dir_win="$(to_windows_path "$release_dir")"
  zip_path_win="$(to_windows_path "$zip_path")"
  powershell.exe -NoProfile -Command \
    "if (Test-Path '$zip_path_win') { Remove-Item '$zip_path_win' -Force }; Compress-Archive -Path '$release_dir_win\\*' -DestinationPath '$zip_path_win' -Force" >/dev/null

  build_windows_installer "$release_dir"
}

download_appimagetool() {
  local arch="$1"
  local tool_path="$2"
  local tool_arch
  tool_arch="$(linux_appimage_arch "$arch")"
  curl -fsSL \
    "https://github.com/AppImage/appimagetool/releases/download/${APPIMAGE_TOOL_VERSION}/appimagetool-${tool_arch}.AppImage" \
    -o "$tool_path"
  chmod +x "$tool_path"
}

write_linux_apprun() {
  local apprun_path="$1"
  cat > "$apprun_path" <<'EOF'
#!/usr/bin/env sh
# Launch the packaged Flutter binary from inside the AppImage mount point.
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$HERE/remote_storage" "$@"
EOF
  chmod +x "$apprun_path"
}

write_linux_desktop_file() {
  local desktop_path="$1"
  cat > "$desktop_path" <<'EOF'
[Desktop Entry]
Type=Application
Name=云卷
Comment=Local Manager for Remote Volumes
Exec=remote_storage
Icon=yunjuan
Terminal=false
Categories=Network;FileTools;
StartupNotify=true
EOF
}

build_linux() {
  require_cmd flutter
  require_cmd go
  require_cmd curl
  mkdir -p "$ROOT_DIR/bin/bridge" "$OUTPUT_DIR"

  local flutter_target build_arch bundle_dir bridge_so appimage_arch
  flutter_target="$(linux_flutter_target "$ARCH")"
  build_arch="$(linux_build_arch "$ARCH")"
  bridge_so="$ROOT_DIR/bin/bridge/libremote_storage_bridge.so"
  (
    cd "$ROOT_DIR"
    if [[ -n "${BRIDGE_CC:-}" ]]; then
      export CC="$BRIDGE_CC"
    fi
    env CGO_ENABLED=1 GOOS=linux GOARCH="$(linux_go_arch "$ARCH")" \
      go build -buildmode=c-shared -o "$bridge_so" ./bridge
    flutter build linux --release \
      --target-platform "$flutter_target" \
      --dart-define APP_VERSION_LABEL=$VERSION \
      --build-name "$VERSION" \
      --build-number "$BUILD_NUMBER"
  )

  bundle_dir="$(linux_bundle_dir "$build_arch")"
  [[ -d "$bundle_dir" ]] || fail "Linux bundle directory not found: $bundle_dir"
  cp "$bridge_so" "$bundle_dir/libremote_storage_bridge.so"

  local temp_dir app_dir tool_path appimage_path tarball_path
  temp_dir="$(mktemp -d)"
  app_dir="$temp_dir/${APP_NAME}.AppDir"
  mkdir -p "$app_dir"
  cp -R "$bundle_dir"/. "$app_dir/"
  cp "$ROOT_DIR/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png" "$app_dir/yunjuan.png"
  write_linux_apprun "$app_dir/AppRun"
  write_linux_desktop_file "$app_dir/yunjuan.desktop"

  tarball_path="$OUTPUT_DIR/$ARTIFACT_PREFIX-linux-$ARCH.tar.gz"
  package_linux_tarball "$bundle_dir" "$tarball_path"

  tool_path="$temp_dir/appimagetool.AppImage"
  download_appimagetool "$ARCH" "$tool_path"

  appimage_arch="$(linux_appimage_arch "$ARCH")"
  appimage_path="$OUTPUT_DIR/$ARTIFACT_PREFIX-linux-$ARCH.AppImage"
  APPIMAGE_EXTRACT_AND_RUN=1 ARCH="$appimage_arch" "$tool_path" "$app_dir" "$appimage_path" >/dev/null
  rm -rf "$temp_dir"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)
      PLATFORM="${2:-}"
      shift 2
      ;;
    --arch)
      ARCH="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$PLATFORM" ]] || fail "--platform is required"
[[ -n "$VERSION" ]] || fail "--version is required"
OUTPUT_DIR="$(resolve_output_dir "$OUTPUT_DIR")"
ARCH="${ARCH:-$(detect_arch)}"

case "$PLATFORM" in
  windows) build_windows ;;
  macos) build_macos ;;
  linux) build_linux ;;
  *) fail "Unsupported platform: $PLATFORM" ;;
esac
