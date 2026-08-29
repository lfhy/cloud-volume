#!/usr/bin/env bash
# make android-run driver for macOS Android debugging: builds both bridge ABIs
# (arm64-v8a + x86_64, so physical ARM devices and either emulator arch work),
# boots the "cloud-volume" AVD when no device is attached, waits for boot, then
# hands over to `flutter run` on the resolved device serial.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$script_dir/android_env.sh"

usage() {
  cat <<'EOF'
Usage: scripts/run_android.sh [options]
  --sdk-root PATH   Android SDK root (default: ANDROID_SDK_ROOT or ~/Library/Android/sdk)
  --avd NAME        AVD to boot (default: cloud-volume)
  --headless        Boot the emulator without a window
  --boot-only       Stop after the emulator is booted (no flutter run)
  --skip-bridge     Skip the Android bridge builds
Env: CV_DEBUG_ADDR (device loopback debug endpoint, auto adb-forwarded),
     CV_EMU_BOOT_TIMEOUT (seconds, default 300)
EOF
}

die() { echo "run_android.sh: $*" >&2; exit 1; }
section() { echo; echo "==> $1"; }

avd_name=cloud-volume
sdk_root="$(cv_sdk_root)"
headless=0 boot_only=0 skip_bridge=0
while [ $# -gt 0 ]; do
  case "$1" in
    --sdk-root) sdk_root="${2:?missing value}"; shift 2 ;;
    --avd) avd_name="${2:?missing value}"; shift 2 ;;
    --headless) headless=1; shift ;;
    --boot-only) boot_only=1; shift ;;
    --skip-bridge) skip_bridge=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

adb="$sdk_root/platform-tools/adb"
emulator_bin="$sdk_root/emulator/emulator"
avdmanager="$sdk_root/cmdline-tools/latest/bin/avdmanager"

[ -x "$adb" ] || die "adb not found at $adb — run scripts/setup_android_dev.sh first"
flutter_bin="$(cv_flutter_bin || true)"
[ -n "$flutter_bin" ] || die 'flutter not found — run scripts/setup_android_dev.sh first'
command -v go >/dev/null 2>&1 || die 'go not found in PATH (the bridge cross-compile needs it)'
# Gradle (flutter run's Android build) needs a JDK; resolve one when the
# caller's shell does not carry JAVA_HOME.
if cv_java_home >/dev/null 2>&1; then
  export JAVA_HOME="$(cv_java_home)"
fi
export ANDROID_SDK_ROOT="$sdk_root"
export ANDROID_HOME="$sdk_root"

repo_root="$(dirname "$script_dir")"
mkdir -p "$repo_root/build/logs"

if [ "$skip_bridge" -eq 0 ]; then
  section 'Building Android bridge (arm64-v8a + x86_64)'
  "$script_dir/build_android_bridge.sh" --sdk-root "$sdk_root" --abi arm64-v8a
  "$script_dir/build_android_bridge.sh" --sdk-root "$sdk_root" --abi x86_64
fi

first_online_serial() { "$adb" devices 2>/dev/null | awk '$2=="device"{print $1; exit}' || true; }

section 'Waiting for an Android device'
"$adb" start-server >/dev/null 2>&1 || true
serial="$(first_online_serial)"
if [ -z "$serial" ] && "$adb" devices | awk '$2=="unauthorized"{found=1} END{exit !found}'; then
  echo 'Note: an unauthorized device is attached — accept its USB debugging prompt to use it instead of the emulator.'
fi

if [ -z "$serial" ]; then
  [ -x "$emulator_bin" ] || die "emulator not found at $emulator_bin — rerun scripts/setup_android_dev.sh (without --skip-emulator)"
  # Matches the image installed by setup_android_dev.sh: arm64-v8a on Apple
  # Silicon (native emulator + HVF), x86_64 on Intel.
  image_abi=x86_64
  if [ "$(cv_host_arch)" = arm64 ]; then image_abi=arm64-v8a; fi
  if ! "$avdmanager" list avd 2>/dev/null | grep -q "Name: $avd_name$"; then
    section "Creating AVD $avd_name"
    echo no | "$avdmanager" create avd -n "$avd_name" \
      -k "system-images;android-36;google_apis;$image_abi" --device pixel_6 \
      || die "AVD creation failed — the system image may be missing; rerun scripts/setup_android_dev.sh"
  fi
  section "Booting emulator $avd_name (log: build/logs/android-emulator.log)"
  extra_flags=''
  if [ "$headless" -eq 1 ]; then extra_flags='-no-window'; fi
  # The emulator outlives flutter run: INT/QUIT/TERM are ignored before exec so
  # Ctrl-C in the flutter session does not tear the emulator down with it.
  ( trap '' INT QUIT TERM
    exec "$emulator_bin" -avd "$avd_name" -netdelay none -netspeed full -no-boot-anim $extra_flags
  ) >"$repo_root/build/logs/android-emulator.log" 2>&1 &
  register_deadline=$((SECONDS + 120))
  while [ -z "$serial" ] && [ "$SECONDS" -lt "$register_deadline" ]; do
    sleep 2
    serial="$(first_online_serial)"
  done
  [ -n "$serial" ] || die "emulator did not register with adb within 120s — check build/logs/android-emulator.log"
fi

section "Waiting for Android boot on $serial"
boot_timeout="${CV_EMU_BOOT_TIMEOUT:-300}"
boot_deadline=$((SECONDS + boot_timeout))
while :; do
  # A single transient adb failure (device still coming up, server hiccup)
  # must not kill the script; the timeout branch below handles real stalls.
  boot_state="$("$adb" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
  if [ "$boot_state" = "1" ]; then
    break
  fi
  if [ "$SECONDS" -ge "$boot_deadline" ]; then
    die "device did not finish booting within ${boot_timeout}s — check build/logs/android-emulator.log"
  fi
  sleep 3
done
echo "Device ready: $serial"

if [ -n "${CV_DEBUG_ADDR:-}" ]; then
  port="${CV_DEBUG_ADDR##*:}"
  case "$port" in
    ''|*[!0-9]*) die "cannot parse a numeric port from CV_DEBUG_ADDR=$CV_DEBUG_ADDR" ;;
  esac
  section "Forwarding device debug endpoint ($CV_DEBUG_ADDR)"
  "$adb" -s "$serial" forward "tcp:$port" "tcp:$port" >/dev/null
  set -- --dart-define=CV_DEBUG_ADDR="$CV_DEBUG_ADDR"
else
  set --
fi

if [ "$boot_only" -eq 1 ]; then
  echo "Emulator booted (serial: $serial). Re-run without --boot-only to attach flutter run."
  exit 0
fi

section 'flutter run'
cd "$repo_root"
"$flutter_bin" pub get
exec "$flutter_bin" run -d "$serial" --dart-define=APP_VERSION_LABEL=dev "$@"
