#!/usr/bin/env bash
# Bootstraps the user-scoped Android toolchain on macOS (Unix mirror of
# setup_android_dev.ps1): Temurin JDK 17, Flutter (reused from PATH when
# present, otherwise installed to ~/dev/flutter), Android SDK command-line
# tools + platform-tools + API 36 + Build Tools 36.0.0 + NDK 28.2.13676358 +
# emulator with a host-matching Google APIs system image, and a ready-to-boot
# "cloud-volume" AVD. Afterwards `make android-run` works on this machine.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$script_dir/android_env.sh"

usage() {
  cat <<'EOF'
Usage: scripts/setup_android_dev.sh [options]
  --sdk-root PATH       Android SDK root (default: ~/Library/Android/sdk)
  --java-home PATH      JDK 17 install dir (default: ~/dev/jdk-17)
  --flutter-archive F   Local Flutter macOS zip for offline install
  --skip-emulator       Skip system image download and AVD creation
  --skip-validation     Skip flutter pub get / flutter test
  --no-shellrc          Do not append env exports to ~/.zshrc
Env overrides: CV_JDK_ARCHIVE_URL, CV_FLUTTER_ARCHIVE_URL, FLUTTER_STORAGE_BASE_URL
EOF
}

die() { echo "setup_android_dev.sh: $*" >&2; exit 1; }
section() { echo; echo "==> $1"; }

skip_emulator=0 skip_validation=0 no_shellrc=0
# Respect ANDROID_SDK_ROOT/ANDROID_HOME like the sibling scripts do.
sdk_root="$(cv_sdk_root)"
java_target="$HOME/dev/jdk-17"
flutter_archive=''
while [ $# -gt 0 ]; do
  case "$1" in
    --sdk-root) sdk_root="${2:?missing value}"; shift 2 ;;
    --java-home) java_target="${2:?missing value}"; shift 2 ;;
    --flutter-archive) flutter_archive="${2:?missing value}"; shift 2 ;;
    --skip-emulator) skip_emulator=1; shift ;;
    --skip-validation) skip_validation=1; shift ;;
    --no-shellrc) no_shellrc=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

[ "$(cv_host_os)" = darwin ] || die "this bootstrap targets macOS; on Windows use scripts/setup_android_dev.ps1"

# Emulator image ABI follows the host CPU: arm64-v8a on Apple Silicon (native
# aarch64 emulator + Hypervisor.framework), x86_64 on Intel.
image_abi=x86_64
adopt_arch=x64
if [ "$(cv_host_arch)" = arm64 ]; then
  image_abi=arm64-v8a
  adopt_arch=aarch64
fi

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cv-android-setup.XXXXXX")"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

section 'JDK 17'
resolved_java_home="$(cv_java_home || true)"
if [ -n "$resolved_java_home" ]; then
  echo "Using existing JDK: $resolved_java_home"
elif [ -x "$java_target/Contents/Home/bin/java" ]; then
  resolved_java_home="$java_target/Contents/Home"
  echo "Using existing JDK: $resolved_java_home"
elif [ -x "$java_target/bin/java" ]; then
  resolved_java_home="$java_target"
  echo "Using existing JDK: $resolved_java_home"
else
  if [ -e "$java_target" ]; then
    die "refusing to replace existing incomplete JDK dir: $java_target"
  fi
  jdk_url="${CV_JDK_ARCHIVE_URL:-https://api.adoptium.net/v3/binary/latest/17/ga/mac/$adopt_arch/jdk/hotspot/normal/eclipse}"
  echo "Downloading Temurin JDK 17 ($adopt_arch)... $jdk_url"
  curl -fL --retry 3 --retry-delay 2 -o "$tmpdir/jdk.tar.gz" "$jdk_url" \
    || die "JDK download failed (set CV_JDK_ARCHIVE_URL to use a mirror)"
  tar -xzf "$tmpdir/jdk.tar.gz" -C "$tmpdir"
  # macOS JDK tarballs use the bundle layout <root>/Contents/Home.
  extracted_home="$(find "$tmpdir" -maxdepth 4 -type d -path '*/Contents/Home' | head -n 1)"
  [ -n "$extracted_home" ] || die "unexpected JDK archive layout (no Contents/Home)"
  mkdir -p "$(dirname "$java_target")"
  mv "$(dirname "$(dirname "$extracted_home")")" "$java_target"
  resolved_java_home="$java_target/Contents/Home"
  echo "Installed JDK 17: $java_target"
fi
export JAVA_HOME="$resolved_java_home"
export PATH="$JAVA_HOME/bin:$PATH"

section 'Flutter'
flutter_bin="$(cv_flutter_bin || true)"
flutter_installed=0
if [ -n "$flutter_bin" ]; then
  echo "Using Flutter already on PATH: $flutter_bin"
else
  flutter_target="$HOME/dev/flutter"
  if [ -x "$flutter_target/bin/flutter" ]; then
    echo "Using existing Flutter: $flutter_target"
  else
    if [ -z "$flutter_archive" ]; then
      if [ -n "${CV_FLUTTER_ARCHIVE_URL:-}" ]; then
        archive_url="$CV_FLUTTER_ARCHIVE_URL"
      else
        dart_arch=x64
        if [ "$(cv_host_arch)" = arm64 ]; then dart_arch=arm64; fi
        storage_base="${FLUTTER_STORAGE_BASE_URL:-https://storage.googleapis.com}"
        echo "Resolving current Flutter stable ($dart_arch)..."
        # Download the manifest to a file first: piping it into `python3 -` would
        # collide with the heredoc that carries the program via stdin.
        curl -fsSL --retry 3 -o "$tmpdir/releases_macos.json" "$storage_base/flutter_infra_release/releases/releases_macos.json" \
          || die "could not download the Flutter release manifest"
        archive_url="$(python3 - "$dart_arch" "$tmpdir/releases_macos.json" <<'PY'
import json,sys
manifest = json.load(open(sys.argv[2]))
stable = manifest["current_release"]["stable"]
for release in manifest["releases"]:
    if release["hash"] == stable and release.get("dart_sdk_arch", "x64") == sys.argv[1]:
        print(manifest["base_url"] + "/" + release["archive"])
        break
else:
    sys.exit(1)
PY
        )" || die "could not resolve the Flutter stable archive (set CV_FLUTTER_ARCHIVE_URL or --flutter-archive)"
      fi
      flutter_archive="$tmpdir/flutter.zip"
      curl -fL --retry 3 --retry-delay 2 -o "$flutter_archive" "$archive_url" \
        || die "Flutter archive download failed"
    elif [ ! -f "$flutter_archive" ]; then
      die "flutter archive not found: $flutter_archive"
    fi
    unzip -q "$flutter_archive" -d "$tmpdir/flutter-extract"
    [ -d "$tmpdir/flutter-extract/flutter" ] || die "unexpected Flutter archive layout (no flutter/ root)"
    mkdir -p "$(dirname "$flutter_target")"
    if [ -e "$flutter_target" ]; then
      die "refusing to replace existing incomplete Flutter dir: $flutter_target"
    fi
    mv "$tmpdir/flutter-extract/flutter" "$flutter_target"
    # Flutter is a git checkout; modern git refuses to run in it otherwise.
    git config --global --add safe.directory "$flutter_target" 2>/dev/null || true
    flutter_installed=1
    echo "Installed Flutter stable: $flutter_target"
  fi
  flutter_bin="$flutter_target/bin/flutter"
fi
export PATH="$(dirname "$flutter_bin"):$PATH"

section 'Android SDK command-line tools'
cmdline_tools="$sdk_root/cmdline-tools/latest"
sdkmanager="$cmdline_tools/bin/sdkmanager"
avdmanager="$cmdline_tools/bin/avdmanager"
if [ ! -x "$sdkmanager" ]; then
  command -v xmllint >/dev/null 2>&1 \
    || die "xmllint (from macOS Command Line Tools) is required to resolve the cmdline-tools archive"
  echo 'Resolving Android command-line tools archive...'
  curl -fsSL --retry 3 -o "$tmpdir/repository2-1.xml" https://dl.google.com/android/repository/repository2-1.xml
  # The repository XML tags macOS archives as host-os "macosx" (older ones "mac").
  tools_path="$(xmllint --xpath \
    "//*[local-name()='remotePackage' and @path='cmdline-tools;latest']//*[local-name()='archive'][*[local-name()='host-os' and (text()='macosx' or text()='mac')]]/*[local-name()='complete']/*[local-name()='url']/text()" \
    "$tmpdir/repository2-1.xml" 2>/dev/null || true)"
  [ -n "$tools_path" ] || die "could not resolve the Android command-line tools archive"
  curl -fL --retry 3 --retry-delay 2 -o "$tmpdir/cmdline-tools.zip" "https://dl.google.com/android/repository/$tools_path"
  unzip -q "$tmpdir/cmdline-tools.zip" -d "$tmpdir/clt-extract"
  [ -d "$tmpdir/clt-extract/cmdline-tools" ] || die "unexpected cmdline-tools archive layout"
  mkdir -p "$sdk_root/cmdline-tools"
  if [ -e "$cmdline_tools" ]; then
    die "refusing to replace existing incomplete cmdline-tools: $cmdline_tools"
  fi
  mv "$tmpdir/clt-extract/cmdline-tools" "$cmdline_tools"
  echo "Installed command-line tools: $cmdline_tools"
else
  echo "Using existing command-line tools: $cmdline_tools"
fi
export ANDROID_SDK_ROOT="$sdk_root"
export ANDROID_HOME="$sdk_root"
export PATH="$cmdline_tools/bin:$sdk_root/platform-tools:$sdk_root/emulator:$PATH"

section 'Android SDK licenses'
# cmdline-tools 23 deprecates --licenses ("no longer needed") and may return
# non-zero on it or on its first invocation; older tools still require
# acceptance. Feed a finite answers file (no `yes |` pipe: under pipefail the
# broken pipe turns a successful sdkmanager run into a failure) and only die
# when neither the exit code nor the deprecation notice applies.
license_answers="$tmpdir/licenses-answers.txt"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    echo y
  done
done >"$license_answers"
licenses_ok=0
for attempt in 1 2; do
  if "$sdkmanager" --licenses <"$license_answers" >"$tmpdir/licenses.log" 2>&1; then
    licenses_ok=1
    break
  fi
  if grep -q 'no longer needed' "$tmpdir/licenses.log"; then
    licenses_ok=1
    break
  fi
done
if [ "$licenses_ok" -ne 1 ]; then
  tail -n 20 "$tmpdir/licenses.log" >&2
  die "sdkmanager --licenses failed"
fi

section 'Android SDK packages'
# The NDK is pinned: the Go bridge cross-compiles with this exact toolchain.
"$sdkmanager" 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' 'ndk;28.2.13676358' 'emulator'
if [ "$skip_emulator" -ne 1 ]; then
  "$sdkmanager" "system-images;android-36;google_apis;$image_abi"
fi

if [ "$skip_emulator" -ne 1 ] && [ "$(cv_host_arch)" = arm64 ]; then
  # The legacy sdkmanager consults repository2-1, whose macOS emulator archives
  # are x86_64-only; that build cannot run arm64 system images (HVF init fails
  # under Rosetta). Replace it with the native aarch64 archive of the same
  # stable version, resolved from repository2-3 (Android Studio's channel).
  if [ -d "$sdk_root/emulator/qemu/darwin-aarch64" ] && [ -f "$sdk_root/emulator/package.xml" ]; then
    echo 'Native aarch64 emulator already installed; skipping replacement.'
  else
    echo 'Replacing the x86_64 emulator with the native aarch64 build...'
    saved_package_xml="$tmpdir/emulator-package.xml"
    cp "$sdk_root/emulator/package.xml" "$saved_package_xml"
    curl -fsSL --retry 3 -o "$tmpdir/repository2-3.xml" https://dl.google.com/android/repository/repository2-3.xml
    emu_url="$(python3 - "$tmpdir/repository2-3.xml" <<'PY'
import re, sys
xml = open(sys.argv[1]).read()
for pkg in re.findall(r'<remotePackage[^>]*path="emulator"[^>]*>.*?</remotePackage>', xml, re.S):
    if 'channel-0' not in pkg:  # stable channel only
        continue
    for archive in re.finditer(r'<archive>(.*?)</archive>', pkg, re.S):
        body = archive.group(1)
        if '<host-os>macosx</host-os>' in body and '<arch>aarch64</arch>' in body:
            url = re.search(r'<url>([^<]+)</url>', body)
            if url:
                print('https://dl.google.com/android/repository/' + url.group(1))
                sys.exit(0)
    break
sys.exit(1)
PY
)"
    [ -n "$emu_url" ] || die 'could not resolve the aarch64 emulator archive from repository2-3'
    curl -fL --retry 3 --retry-delay 2 -o "$tmpdir/emulator-aarch64.zip" "$emu_url"
    # Extract before removing the old tree so a failed download/extract never
    # leaves the SDK without an emulator.
    rm -rf "$tmpdir/emu-extract"
    unzip -q "$tmpdir/emulator-aarch64.zip" -d "$tmpdir/emu-extract"
    [ -d "$tmpdir/emu-extract/emulator" ] || die 'unexpected aarch64 emulator archive layout'
    rm -rf "$sdk_root/emulator"
    mv "$tmpdir/emu-extract/emulator" "$sdk_root/emulator"
    # The aarch64 archive ships no package.xml; restore the sdkmanager one so
    # avdmanager still recognizes the installed "emulator" package.
    cp "$saved_package_xml" "$sdk_root/emulator/package.xml"
    echo "Installed native aarch64 emulator: $sdk_root/emulator"
  fi
fi

if [ "$(cv_host_arch)" = arm64 ]; then
  # The NDK host toolchain is x86_64 and needs Rosetta 2 on Apple Silicon
  # (the native aarch64 emulator does not, but run_android.sh's bridge builds do).
  cv_ensure_rosetta \
    || echo 'WARNING: Rosetta 2 install failed; install manually with: softwareupdate --install-rosetta --agree-to-license'
fi

if [ "$skip_emulator" -ne 1 ]; then
  section 'Android emulator AVD'
  if "$avdmanager" list avd 2>/dev/null | grep -q "Name: cloud-volume$"; then
    echo 'Using existing AVD: cloud-volume'
  else
    echo no | "$avdmanager" create avd -n cloud-volume \
      -k "system-images;android-36;google_apis;$image_abi" --device pixel_6
    echo 'Created AVD: cloud-volume'
  fi
fi

section 'Flutter Android configuration'
"$flutter_bin" config --android-sdk "$sdk_root"
"$flutter_bin" doctor -v

if [ "$no_shellrc" -ne 1 ]; then
  section 'Shell environment (~/.zshrc)'
  zshrc="$HOME/.zshrc"
  if [ -f "$zshrc" ] && grep -q 'cloud-volume android dev' "$zshrc"; then
    echo '~/.zshrc already contains the android dev block'
  else
    flutter_path_entry=''
    if [ "$flutter_installed" -eq 1 ]; then
      flutter_path_entry="$HOME/dev/flutter/bin:"
    fi
    {
      echo '# >>> cloud-volume android dev >>>'
      echo "export JAVA_HOME=\"$resolved_java_home\""
      echo "export ANDROID_HOME=\"$sdk_root\""
      echo "export ANDROID_SDK_ROOT=\"$sdk_root\""
      echo "export PATH=\"$sdk_root/cmdline-tools/latest/bin:$sdk_root/platform-tools:$sdk_root/emulator:$flutter_path_entry\$PATH\""
      echo '# <<< cloud-volume android dev <<<'
    } >> "$zshrc"
    echo 'Appended android dev exports to ~/.zshrc'
  fi
fi

if [ "$skip_validation" -ne 1 ]; then
  section 'Project dependency validation'
  (cd "$(dirname "$script_dir")" && "$flutter_bin" pub get && "$flutter_bin" test)
fi

echo
echo 'Android toolchain setup completed. Open a new terminal (or `source ~/.zshrc`) before using adb/sdkmanager directly.'
