# Shared environment resolution for the Unix-side Android toolchain scripts.
# Sourced by setup_android_dev.sh / build_android_bridge.sh / run_android.sh;
# only lookups and capability probes live here so each entry script owns its
# own workflow and error messages. Written for macOS' bash 3.2.

# Host OS tag: darwin | linux | other.
cv_host_os() {
  case "$(uname -s)" in
    Darwin) printf 'darwin\n' ;;
    Linux) printf 'linux\n' ;;
    *) printf 'other\n' ;;
  esac
}

# Host CPU tag: arm64 | amd64 | other.
cv_host_arch() {
  case "$(uname -m)" in
    arm64) printf 'arm64\n' ;;
    x86_64) printf 'amd64\n' ;;
    *) printf 'other\n' ;;
  esac
}

# Canonical per-host default SDK location (Android Studio's own default).
cv_default_sdk_root() {
  if [ "$(cv_host_os)" = darwin ]; then
    printf '%s\n' "$HOME/Library/Android/sdk"
  else
    printf '%s\n' "$HOME/Android/Sdk"
  fi
}

# ANDROID_SDK_ROOT / ANDROID_HOME win when set, otherwise the per-host default.
cv_sdk_root() {
  if [ -n "${ANDROID_SDK_ROOT:-}" ]; then
    printf '%s\n' "$ANDROID_SDK_ROOT"
  elif [ -n "${ANDROID_HOME:-}" ]; then
    printf '%s\n' "$ANDROID_HOME"
  else
    cv_default_sdk_root
  fi
}

# Absolute path of a usable flutter executable; rc 1 when none is reachable.
cv_flutter_bin() {
  if command -v flutter >/dev/null 2>&1; then
    command -v flutter
    return 0
  fi
  if [ -n "${FLUTTER_ROOT:-}" ] && [ -x "$FLUTTER_ROOT/bin/flutter" ]; then
    printf '%s\n' "$FLUTTER_ROOT/bin/flutter"
    return 0
  fi
  if [ -x /opt/tools/flutter/bin/flutter ]; then
    printf '%s\n' /opt/tools/flutter/bin/flutter
    return 0
  fi
  return 1
}

# Major version of a java binary ('' when it cannot run at all).
cv_java_major() {
  "$1" -version 2>&1 | sed -n '1s/.*version "\([0-9][0-9]*\)[."].*/\1/p' | head -n 1
}

cv_java_major_ok() {
  local major
  major="$(cv_java_major "$1/bin/java")"
  [ -n "$major" ] && [ "$major" -ge 17 ]
}

# Locate a JDK >= 17 for Gradle/sdkmanager: JAVA_HOME, macOS JVM registry,
# PATH-derived install, then the setup script's default. rc 1 when none.
cv_java_home() {
  local candidate
  if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    candidate="$JAVA_HOME"
    if cv_java_major_ok "$candidate"; then printf '%s\n' "$candidate"; return 0; fi
  fi
  if [ "$(cv_host_os)" = darwin ] && [ -x /usr/libexec/java_home ]; then
    if candidate="$(/usr/libexec/java_home -v 17 2>/dev/null)" && [ -n "$candidate" ]; then
      if cv_java_major_ok "$candidate"; then printf '%s\n' "$candidate"; return 0; fi
    fi
  fi
  if command -v java >/dev/null 2>&1; then
    candidate="$(cd "$(dirname "$(command -v java)")/.." && pwd)"
    if [ -x "$candidate/bin/java" ] && cv_java_major_ok "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi
  if [ -x "$HOME/dev/jdk-17/Contents/Home/bin/java" ]; then
    printf '%s\n' "$HOME/dev/jdk-17/Contents/Home"
    return 0
  fi
  if [ -x "$HOME/dev/jdk-17/bin/java" ]; then
    printf '%s\n' "$HOME/dev/jdk-17"
    return 0
  fi
  return 1
}

# The macOS NDK host toolchain ships as x86_64 binaries; Apple Silicon runs it
# through Rosetta 2, so make sure the translation layer is installed.
cv_ensure_rosetta() {
  if [ "$(cv_host_os)" != darwin ] || [ "$(cv_host_arch)" != arm64 ]; then
    return 0
  fi
  if [ -f /Library/Apple/usr/share/rosetta/rosetta ]; then
    return 0
  fi
  echo 'Installing Rosetta 2 (required by the Android NDK host toolchain)...'
  if softwareupdate --install-rosetta --agree-to-license >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Echo the NDK llvm prebuilt dir matching this host; rc 1 when NDK is absent.
cv_ndk_toolchain_dir() {
  local sdk_root="$1" ndk_version="$2" base tag
  base="$sdk_root/ndk/$ndk_version/toolchains/llvm/prebuilt"
  [ -d "$base" ] || return 1
  for tag in "$(cv_host_os)-$(cv_host_arch)" "$(cv_host_os)-x86_64" "$(cv_host_os)-arm64"; do
    if [ -d "$base/$tag" ]; then
      printf '%s\n' "$base/$tag"
      return 0
    fi
  done
  return 1
}
