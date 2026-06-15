#!/usr/bin/env bash
set -euo pipefail

# Build packaged Web runtime artifacts: the Flutter web bundle plus the Linux
# server binary that hosts it.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_PREFIX="${ARTIFACT_PREFIX:-yunjuan}"
OUTPUT_DIR="$ROOT_DIR/dist/web"
GOARCH_VALUE=""
VERSION=""

usage() {
  cat <<'USAGE'
Usage: ./scripts/build_web_release.sh --goarch <amd64|arm64> --version <x.y.z> [options]

Options:
  --goarch <name>          Target Linux architecture for the web server binary
  --version <x.y.z>        Release version embedded with ldflags
  --output-dir <path>      Output directory for packaged artifacts
  -h, --help               Show this help
USAGE
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

resolve_output_dir() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$ROOT_DIR/$1" ;;
  esac
}

archive_name() {
  printf '%s-web-linux-%s.tar.gz\n' "$ARTIFACT_PREFIX" "$1"
}

binary_name() {
  printf 'cloud-volume-web\n'
}

package_archive() {
  local stage_dir="$1"
  local archive_path="$2"
  local base_name
  base_name="$(basename "$stage_dir")"

  rm -f "$archive_path"
  tar -C "$(dirname "$stage_dir")" -czf "$archive_path" "$base_name"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --goarch)
      GOARCH_VALUE="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$(resolve_output_dir "${2:-}")"
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

[[ -n "$GOARCH_VALUE" ]] || fail "--goarch is required"
[[ -n "$VERSION" ]] || fail "--version is required"
[[ "$GOARCH_VALUE" == "amd64" || "$GOARCH_VALUE" == "arm64" ]] || fail "--goarch must be amd64 or arm64"

mkdir -p "$OUTPUT_DIR"

flutter pub get
flutter build web --release --dart-define APP_VERSION_LABEL=$VERSION --wasm-dry-run --pwa-strategy=none

stage_root="$(mktemp -d)"
stage_dir="$stage_root/${ARTIFACT_PREFIX}-web-linux-${GOARCH_VALUE}"
mkdir -p "$stage_dir"

binary_path="$stage_dir/$(binary_name)"
static_root="$stage_dir/web"

cp -R "$ROOT_DIR/build/web" "$static_root"
cp "$ROOT_DIR/README.md" "$stage_dir/README.md"

env \
  CGO_ENABLED=0 \
  GOOS=linux \
  GOARCH="$GOARCH_VALUE" \
  go build \
  -trimpath \
  -ldflags "-s -w -X main.version=$VERSION" \
  -o "$binary_path" \
  ./cmd/web

cat > "$stage_dir/START.txt" <<START
Run on Linux ${GOARCH_VALUE}:
  ./cloud-volume-web --listen :8080 --static-root ./web
START

archive_path="$OUTPUT_DIR/$(archive_name "$GOARCH_VALUE")"
package_archive "$stage_dir" "$archive_path"

rm -rf "$stage_root"
