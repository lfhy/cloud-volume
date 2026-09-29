#!/usr/bin/env bash
set -euo pipefail

# Build and verify a signed, ARM64-only Android release with its Go FFI bridge.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=""
BUILD_NUMBER="1"
OUTPUT_DIR="$ROOT_DIR/dist/android-arm64"
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"

usage() {
  cat <<'EOF'
Usage: ./scripts/build_android_packages.sh --version <x.y.z> [options]

Options:
  --version <x.y.z>       Release version (without the v prefix)
  --build-number <num>    Positive Android version code (default: 1)
  --output-dir <path>     Destination for the signed ARM64 APK
  --sdk-root <path>       Android SDK root (or use ANDROID_SDK_ROOT/ANDROID_HOME)
  -h, --help              Show this help

Signing requires ANDROID_KEYSTORE_FILE (an absolute keystore path),
ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, and ANDROID_KEY_PASSWORD.
EOF
}

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version|--build-number|--output-dir|--sdk-root)
      [ "$#" -ge 2 ] && [ -n "$2" ] || fail "Missing value for $1"
      case "$1" in
        --version) VERSION="$2" ;;
        --build-number) BUILD_NUMBER="$2" ;;
        --output-dir) OUTPUT_DIR="$2" ;;
        --sdk-root) SDK_ROOT="$2" ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown option: $1 (see --help)" ;;
  esac
done

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Version must be x.y.z without a v prefix'
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || fail 'Build number must be a positive integer'

# This packaging entry point never accepts Flutter's debug-key release fallback.
for signing_var in ANDROID_KEYSTORE_FILE ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD; do
  [ -n "${!signing_var:-}" ] || fail "Missing Android release signing environment: $signing_var"
done
case "$ANDROID_KEYSTORE_FILE" in
  /*) [ -f "$ANDROID_KEYSTORE_FILE" ] && [ -r "$ANDROID_KEYSTORE_FILE" ] \
      || fail 'ANDROID_KEYSTORE_FILE must be an existing, readable absolute file' ;;
  *) fail 'ANDROID_KEYSTORE_FILE must be an existing, readable absolute file' ;;
esac

[ -n "$SDK_ROOT" ] && [ -d "$SDK_ROOT" ] || fail 'Android SDK root not found; set ANDROID_SDK_ROOT or --sdk-root'
case "$SDK_ROOT" in
  /*) ;;
  *) fail 'Android SDK root must be an absolute path' ;;
esac
for tool in go flutter unzip; do
  command -v "$tool" >/dev/null 2>&1 || fail "Missing command: $tool"
done
apksigner="$SDK_ROOT/build-tools/36.0.0/apksigner"
[ -x "$apksigner" ] || fail "Missing Android SDK Build Tools 36.0.0 apksigner: $apksigner"

case "$OUTPUT_DIR" in
  /*) ;;
  *) OUTPUT_DIR="$ROOT_DIR/$OUTPUT_DIR" ;;
esac
asset="$OUTPUT_DIR/yunjuan-android-arm64-v$VERSION.apk"
apk="$ROOT_DIR/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
mkdir -p "$OUTPUT_DIR"
# Do not accept an APK left by an earlier build if Flutter changes its output.
rm -f "$asset" "$apk"

cd "$ROOT_DIR"
"$ROOT_DIR/scripts/build_android_bridge.sh" --abi arm64-v8a --sdk-root "$SDK_ROOT"
flutter pub get
flutter build apk --release --split-per-abi --target-platform android-arm64 \
  --build-name "$VERSION" --build-number "$BUILD_NUMBER" \
  --dart-define "APP_VERSION_LABEL=$VERSION"

[ -s "$apk" ] || fail "Release APK not found or empty: $apk"
unzip -Z1 "$apk" | grep -Fx 'lib/arm64-v8a/libremote_storage_bridge.so' >/dev/null \
  || fail 'Release APK lacks the ARM64 Go bridge'
if unzip -Z1 "$apk" | grep '^lib/' | grep -Ev '^lib/arm64-v8a/' >/dev/null; then
  fail 'Release APK contains non-ARM64 native libraries'
fi
"$apksigner" verify "$apk" || fail 'Release APK signature verification failed'
cp "$apk" "$asset"
printf 'Built signed Android ARM64 release: %s\n' "$asset"
