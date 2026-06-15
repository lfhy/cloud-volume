#!/usr/bin/env bash
set -euo pipefail

# Generate a GitHub release body with changelog-style sections plus packaged
# asset checksums so release pages stay readable for end users.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_TAG="${1:-${TARGET_TAG:-}}"
ASSET_DIR="${2:-${ASSET_DIR:-$ROOT_DIR/dist/release}}"
OUTPUT_FILE="${3:-${OUTPUT_FILE:-$ROOT_DIR/dist/release-body.md}}"

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"
}

release_repo() {
  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    printf '%s\n' "$GITHUB_REPOSITORY"
    return
  fi

  local origin
  origin="$(git -C "$ROOT_DIR" config --get remote.origin.url || true)"
  case "$origin" in
    git@github.com:*)
      printf '%s\n' "${origin#git@github.com:}" | sed 's/\.git$//'
      ;;
    https://github.com/*)
      printf '%s\n' "${origin#https://github.com/}" | sed 's/\.git$//'
      ;;
    *)
      printf '%s\n' 'lfhy/cloud-volume'
      ;;
  esac
}

human_size() {
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec-i --suffix=B --format="%.1f" "$1"
    return
  fi
  printf '%sB\n' "$1"
}

previous_tag() {
  local tag="$1"
  git -C "$ROOT_DIR" describe --tags --abbrev=0 "${tag}^" 2>/dev/null || true
}

is_release_asset() {
  local asset="$1"
  [[ "$(cd "$(dirname "$asset")" && pwd)/$(basename "$asset")" != "$(cd "$(dirname "$OUTPUT_FILE")" && pwd)/$(basename "$OUTPUT_FILE")" ]]
}

collect_commits() {
  local range="$1"
  git -C "$ROOT_DIR" log --no-merges --format='%s%x09%h' "$range"
}

is_fix_subject() {
  local lowered
  lowered="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$lowered" == *fix* || "$lowered" == *修复* ]]
}

write_updates() {
  local updates="$1"
  local fixes="$2"

  printf '## 更新记录\n\n'
  if [[ -n "$updates" ]]; then
    printf '%s' "$updates"
  else
    printf '%s\n' '- 暂无。'
  fi

  printf '\n## 问题修复\n\n'
  if [[ -n "$fixes" ]]; then
    printf '%s' "$fixes"
  else
    printf '%s\n' '- 暂无。'
  fi
}

write_download_notes() {
  cat <<'SECTION'
## 下载说明

- macOS 用户优先下载 `macos-universal`，兼容 Apple Silicon 与 Intel Mac。
- Apple Silicon 用户如果只想下载更精简的包，也可以直接使用 `macos-arm64`。
- Windows 用户优先下载 `yunjuan-windows-amd64-installer.exe`；如需绿色版可使用 `.zip` 包。
- Linux 桌面用户可按需选择 `AppImage` 或 `tar.gz`。
- Linux 服务器场景推荐使用 `yunjuan-cli-lite-*`、`yunjuan-cli-full-*` 或 `yunjuan-web-*` 发布包。

SECTION
}

write_macos_notes() {
  cat <<'SECTION'
## macOS 打开提示“已损坏”处理方法

如果 macOS 下载后提示“已损坏”或“无法验证开发者”，通常是系统 Gatekeeper 对未签名发布包的隔离限制，并不一定代表文件真的损坏。

可以按以下方式处理：

- 先将应用拖到“应用程序”目录，再右键选择“打开”。
- 如果系统仍然阻止打开，可在“系统设置 -> 隐私与安全性”中选择“仍要打开”。
- 如果仍提示“已损坏”，可执行下面命令移除隔离属性：

```bash
xattr -dr com.apple.quarantine /Applications/云卷.app
```

如果你是从压缩包里直接运行，也可以把路径替换成实际的 `.app` 路径，例如：

```bash
xattr -dr com.apple.quarantine ~/Downloads/云卷.app
```

SECTION
}

write_cn_mirror_notes() {
  local asset_dir="$1"
  local repo="$2"
  local tag="$3"
  local assets=()
  while IFS= read -r asset; do
    is_release_asset "$asset" || continue
    assets+=("$asset")
  done < <(find "$asset_dir" -maxdepth 1 -type f | sort)

  cat <<'SECTION'
## 国内用户下载建议

如果直接从 GitHub 下载速度较慢，可以尝试使用下面的 GitHub 加速源链接。加速源为第三方服务，若其中一个不可用，可切换另一个或回到 GitHub 原始链接。

| 产物 | GitHub 原始下载 | gh-proxy 加速 | ghfast 加速 |
| --- | --- | --- | --- |
SECTION

  if [[ ${#assets[@]} -eq 0 ]]; then
    printf '| 暂无 | - | - | - |\n'
  else
    local asset basename original_url
    for asset in "${assets[@]}"; do
      basename="$(basename "$asset")"
      original_url="https://github.com/${repo}/releases/download/${tag}/${basename}"
      printf '| `%s` | [GitHub](%s) | [gh-proxy](%s%s) | [ghfast](%s%s) |\n' \
        "$basename" \
        "$original_url" \
        "https://gh-proxy.com/" "$original_url" \
        "https://ghfast.top/" "$original_url"
    done
  fi

  printf '\n'
}

write_assets() {
  local asset_dir="$1"
  local assets=()
  while IFS= read -r asset; do
    is_release_asset "$asset" || continue
    assets+=("$asset")
  done < <(find "$asset_dir" -maxdepth 1 -type f | sort)

  printf '## 构建产物\n\n'
  if [[ ${#assets[@]} -eq 0 ]]; then
    printf '%s\n' '- 暂无。'
    return
  fi

  local asset basename size_bytes size_human checksum
  for asset in "${assets[@]}"; do
    basename="$(basename "$asset")"
    size_bytes="$(stat -c %s "$asset" 2>/dev/null || stat -f %z "$asset")"
    size_human="$(human_size "$size_bytes")"
    checksum="$(sha256sum "$asset" | awk '{print $1}')"
    printf -- '- `%s`\n' "$basename"
    printf '  sha256: `%s`\n' "$checksum"
    printf '  size: `%s`\n' "$size_human"
  done
}

main() {
  [[ -n "$TARGET_TAG" ]] || fail "TARGET_TAG is required"
  [[ -d "$ASSET_DIR" ]] || fail "Asset directory does not exist: $ASSET_DIR"
  require_cmd git
  require_cmd sha256sum

  local prev_tag range repo updates="" fixes=""
  repo="$(release_repo)"
  prev_tag="$(previous_tag "$TARGET_TAG")"
  if [[ -n "$prev_tag" ]]; then
    range="$prev_tag..$TARGET_TAG"
  else
    range="$(git -C "$ROOT_DIR" rev-list --max-parents=0 "$TARGET_TAG")..$TARGET_TAG"
  fi

  while IFS=$'\t' read -r subject hash; do
    [[ -n "${subject:-}" ]] || continue
    local entry="- \`$hash\` $subject"
    if is_fix_subject "$subject"; then
      fixes+="${entry}"$'\n'
    else
      updates+="${entry}"$'\n'
    fi
  done < <(collect_commits "$range")

  {
    printf '# 云卷 %s\n\n' "$TARGET_TAG"
    write_updates "$updates" "$fixes"
    printf '\n'
    write_download_notes
    write_macos_notes
    write_cn_mirror_notes "$ASSET_DIR" "$repo" "$TARGET_TAG"
    write_assets "$ASSET_DIR"
  } > "$OUTPUT_FILE"
}

main "$@"
