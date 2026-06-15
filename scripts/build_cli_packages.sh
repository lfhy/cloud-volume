#!/usr/bin/env bash
set -euo pipefail

# Build standalone CLI release artifacts for cross-platform distribution.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_PREFIX="${ARTIFACT_PREFIX:-yunjuan}"
OUTPUT_DIR="$ROOT_DIR/dist/cli"
FLUTTER_BIN="${FLUTTER:-flutter}"

GOOS_VALUE=""
GOARCH_VALUE=""
VERSION=""
VARIANT="lite"

usage() {
  cat <<'USAGE'
Usage: ./scripts/build_cli_packages.sh --goos <linux|darwin|windows> --goarch <amd64|arm64> --version <x.y.z> [options]

Options:
  --goos <name>            Target GOOS
  --goarch <name>          Target GOARCH
  --version <x.y.z>        Release version embedded with ldflags
  --variant <lite|full>    CLI package variant, default is lite
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
  local variant="$1"
  local goos="$2"
  local goarch="$3"
  case "$goos" in
    windows) printf '%s-cli-%s-%s-%s.zip\n' "$ARTIFACT_PREFIX" "$variant" "$goos" "$goarch" ;;
    *) printf '%s-cli-%s-%s-%s.tar.gz\n' "$ARTIFACT_PREFIX" "$variant" "$goos" "$goarch" ;;
  esac
}

stage_dir_name() {
  local variant="$1"
  local goos="$2"
  local goarch="$3"
  printf '%s-cli-%s-%s-%s\n' "$ARTIFACT_PREFIX" "$variant" "$goos" "$goarch"
}

binary_name() {
  local variant="$1"
  local goos="$2"
  case "$goos" in
    windows)
      if [[ "$variant" == "full" ]]; then
        printf 'cloud-volume-cli-full.exe\n'
      else
        printf 'cloud-volume-cli.exe\n'
      fi
      ;;
    *)
      if [[ "$variant" == "full" ]]; then
        printf 'cloud-volume-cli-full\n'
      else
        printf 'cloud-volume-cli\n'
      fi
      ;;
  esac
}

package_archive() {
  local stage_dir="$1"
  local archive_path="$2"
  local base_name
  base_name="$(basename "$stage_dir")"

  rm -f "$archive_path"
  case "$archive_path" in
    *.zip)
      (
        cd "$(dirname "$stage_dir")"
        zip -qr "$archive_path" "$base_name"
      )
      ;;
    *.tar.gz)
      tar -C "$(dirname "$stage_dir")" -czf "$archive_path" "$base_name"
      ;;
    *)
      fail "Unsupported archive format: $archive_path"
      ;;
  esac
}

cleanup_embedded_assets() {
  local embedded_dir="$ROOT_DIR/cmd/cloud-volume-cli/embedded_web"
  rm -rf "$embedded_dir"
  mkdir -p "$embedded_dir"
  printf '*\n!.gitignore\n' > "$embedded_dir/.gitignore"
}

prepare_full_assets() {
  command -v "$FLUTTER_BIN" >/dev/null 2>&1 || fail "Flutter is required for --variant full"
  (
    cd "$ROOT_DIR"
    "$FLUTTER_BIN" pub get
    "$FLUTTER_BIN" build web --release --dart-define APP_VERSION_LABEL=$VERSION --wasm-dry-run --pwa-strategy=none
  )
  cleanup_embedded_assets
  cp -R "$ROOT_DIR/build/web/." "$ROOT_DIR/cmd/cloud-volume-cli/embedded_web/"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --goos)
      GOOS_VALUE="${2:-}"
      shift 2
      ;;
    --goarch)
      GOARCH_VALUE="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --variant)
      VARIANT="${2:-}"
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

[[ -n "$GOOS_VALUE" ]] || fail "--goos is required"
[[ -n "$GOARCH_VALUE" ]] || fail "--goarch is required"
[[ -n "$VERSION" ]] || fail "--version is required"
[[ "$VARIANT" == "lite" || "$VARIANT" == "full" ]] || fail "--variant must be lite or full"

mkdir -p "$OUTPUT_DIR"
cleanup_embedded_assets

stage_root="$(mktemp -d)"
stage_dir="$stage_root/$(stage_dir_name "$VARIANT" "$GOOS_VALUE" "$GOARCH_VALUE")"
mkdir -p "$stage_dir"

binary_path="$stage_dir/$(binary_name "$VARIANT" "$GOOS_VALUE")"
trap 'cleanup_embedded_assets; rm -rf "$stage_root"' EXIT

if [[ "$VARIANT" == "full" ]]; then
  prepare_full_assets
  BUILD_TAG_ARGS=( -tags cli_full )
else
  BUILD_TAG_ARGS=()
fi

env CGO_ENABLED=0 GOOS="$GOOS_VALUE" GOARCH="$GOARCH_VALUE" \
  go build \
  "${BUILD_TAG_ARGS[@]}" \
  -trimpath \
  -ldflags "-s -w -X main.version=$VERSION" \
  -o "$binary_path" \
  ./cmd/cloud-volume-cli

cp "$ROOT_DIR/README.md" "$stage_dir/README.md"
if [[ "$VARIANT" == "full" ]]; then
  cat > "$stage_dir/START.txt" <<START
Run the embedded web console:
  ./$(binary_name "$VARIANT" "$GOOS_VALUE") web --listen :8080
START
fi

archive_path="$OUTPUT_DIR/$(archive_name "$VARIANT" "$GOOS_VALUE" "$GOARCH_VALUE")"
package_archive "$stage_dir" "$archive_path"
