#!/usr/bin/env bash
# Cross-compiles the Go FFI bridge for Android with the NDK installed by
# setup_android_dev.sh (Unix mirror of build_android_bridge.ps1). The output
# lands in android/app/src/main/jniLibs/<abi>/libremote_storage_bridge.so,
# which the Flutter Android runner loads through FFI.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$script_dir/android_env.sh"

usage() {
  cat <<'EOF'
Usage: scripts/build_android_bridge.sh [options]
  --abi ABI          arm64-v8a (default) or x86_64
  --sdk-root PATH    Android SDK root (default: ANDROID_SDK_ROOT or ~/Library/Android/sdk)
  --ndk-version V    NDK version (default: 28.2.13676358)
  --api-level N      Android API the clang wrapper targets (default: 24)
EOF
}

die() { echo "build_android_bridge.sh: $*" >&2; exit 1; }

abi=arm64-v8a
sdk_root="$(cv_sdk_root)"
ndk_version=28.2.13676358
api_level=24
while [ $# -gt 0 ]; do
  case "$1" in
    --abi) abi="${2:?missing value}"; shift 2 ;;
    --sdk-root) sdk_root="${2:?missing value}"; shift 2 ;;
    --ndk-version) ndk_version="${2:?missing value}"; shift 2 ;;
    --api-level) api_level="${2:?missing value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

case "$abi" in
  arm64-v8a) clang_prefix=aarch64-linux-android; go_arch=arm64 ;;
  x86_64) clang_prefix=x86_64-linux-android; go_arch=amd64 ;;
  *) die "unsupported abi: $abi (expected arm64-v8a or x86_64)" ;;
esac

toolchain="$(cv_ndk_toolchain_dir "$sdk_root" "$ndk_version" || true)"
if [ -z "$toolchain" ]; then
  die "Android NDK $ndk_version not found under $sdk_root — install it with: sdkmanager \"ndk;$ndk_version\" (or run scripts/setup_android_dev.sh)"
fi
compiler="$toolchain/bin/${clang_prefix}${api_level}-clang"
[ -x "$compiler" ] || die "missing NDK compiler wrapper: $compiler"

# The macOS NDK host toolchain is x86_64; Apple Silicon runs it through Rosetta 2.
if [ "$(cv_host_os)" = darwin ] && [ "$(cv_host_arch)" = arm64 ]; then
  cv_ensure_rosetta \
    || die 'Rosetta 2 is required by the NDK toolchain; install with: softwareupdate --install-rosetta --agree-to-license'
fi

command -v go >/dev/null 2>&1 || die 'go toolchain not found in PATH'

repo_root="$(dirname "$script_dir")"
output_dir="$repo_root/android/app/src/main/jniLibs/$abi"
library="$output_dir/libremote_storage_bridge.so"
mkdir -p "$output_dir"

# GOPROXY/GOSUMDB default to the CN mirrors (same as build_android_bridge.ps1);
# existing environment values win.
GOOS=android GOARCH="$go_arch" CGO_ENABLED=1 CC="$compiler" \
GOPROXY="${GOPROXY:-https://goproxy.cn,direct}" GOSUMDB="${GOSUMDB:-sum.golang.google.cn}" \
  go build -buildmode=c-shared -ldflags "-X main.buildArch=$go_arch" -o "$library" "$repo_root/bridge"

# The generated C header is an intermediate of the c-shared build, not an APK asset.
rm -f "$output_dir/libremote_storage_bridge.h"
echo "Built Android bridge ($abi): $library"
