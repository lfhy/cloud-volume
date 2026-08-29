# Agent Note: macOS Android 调测链——setup/bridge/run 三脚本与 make android-run

Status: implemented

## Problem

仓库的 Android 开发链只有 Windows 路径(`setup_android_dev.ps1` 引导、`build_android.ps1` 出包),macOS 开发机上没有任何引导或调测入口:手动装 JDK/Android SDK/NDK 步骤多且易错,Apple Silicon 还叠加多层架构坑(NDK 宿主链、模拟器二进制、系统镜像各有独立架构),也没有"启动模拟器→跑 app"的一键回路。需求是 `make android-run` 在 macOS 上可直接调测 Android 版本。

## Decision

补一条与 Windows 路径对称、按 macOS 习惯收敛的 Unix 工具链,入口收敛进 Makefile:

- `scripts/android_env.sh` — 三个脚本共享的解析 helper(Flutter/JDK ≥17/SDK 根定位、Rosetta 与 NDK 探测),按 macOS 自带 bash 3.2 语法书写。
- `scripts/setup_android_dev.sh` — 引导:复用 PATH 上的 Flutter(缺失时按 releases_macos manifest 装 stable,`--flutter-archive`/`CV_FLUTTER_ARCHIVE_URL` 离线逃生;不钉版本,桌面链已证明可用即可);Temurin JDK 17 直连 Adoptium 装 `~/dev/jdk-17`(已有 ≥17 JDK 复用);Android SDK 默认 `~/Library/Android/sdk`,装 cmdline-tools、platform-tools、API 36、Build Tools 36.0.0、NDK 28.2.13676358、emulator 与按主机 ABI 的 Google APIs 镜像,建 `cloud-volume` AVD(pixel_6);往 `~/.zshrc` 追加带标记的导出块,末尾 doctor/pub get/flutter test。
- `scripts/build_android_bridge.sh` — `build_android_bridge.ps1` 的 Unix 版:NDK + `GOOS=android` 交叉编译,NDK 宿主工具链目录按 `darwin-*` glob 自动探测(不写死 darwin-x86_64),Rosetta 由 helper 确保安装。
- `scripts/run_android.sh`(`make android-run`)— 先建 **双 ABI 桥(arm64-v8a + x86_64)**,已有在线物理设备则直接用,否则创建/启动 `cloud-volume` AVD 并轮询 `sys.boot_completed`,再 `flutter run -d <serial>`;`CV_DEBUG_ADDR` 非空时自动 `adb forward` 并透传 dart-define。
- Makefile 新增 `android-setup` / `android-bridge` / `android-run`;Windows 主机报错并指回 ps1 脚本,Makefile 保持薄(逻辑都在脚本里)。

模拟器生命周期:启动时用 `trap '' INT QUIT TERM` 后 `exec`,信号屏蔽跨 exec 生效,使 Ctrl-C 只结束 flutter 会话、模拟器留给下一次 attach;日志写 `build/logs/android-emulator.log`。

**Apple Silicon 的模拟器架构正解(实测钉住):** legacy sdkmanager 走 repository2-1,macOS 只有 x86_64 emulator 归档;该构建跑 arm64 镜像 FATAL(launcher 在 Rosetta 下把 host 判成 x86_64),跑 x86_64 镜像 `HVF Unknown error 0x4`(Rosetta 进程无法用 HVF 虚拟化 x86_64 guest)。setup 在 arm64 主机上自动用 repository2-3 的同版本稳定 `emulator-darwin_aarch64` 归档替换(归档不带 `package.xml`,回填 sdkmanager 的那份,否则 avdmanager 拒绝建 AVD),配 arm64-v8a 镜像走 native HVF。

**Flutter 版本兼容:** `android/app/build.gradle.kts` 显式 apply `org.jetbrains.kotlin.android`(settings 已钉 2.4.0 `apply false`):Flutter 3.47 的 flutter-gradle-plugin 自动补 Kotlin 插件,3.41 不会,导致 macOS 复用 PATH Flutter(3.41.6)时 `kotlin { compilerOptions }` 块解析失败。显式声明对 3.47 幂等(Gradle 插件重复 apply 是 no-op)。

其余钉住的上游事实:repository XML 的 macOS host-os 标记是 `macosx`(旧版 `mac`,ps1 只匹配 windows 未暴露);cmdline-tools 23 弃用 `sdkmanager --licenses`("no longer needed")且首次调用可能非零退出,licenses 步骤按"重试一次 + 输出含 no longer needed 即通过"容忍;flutter doctor 的 license 探针同受 cmdline-tools 23 影响,永远显示 "license status unknown",但 license 文件已写入、构建不受影响。

## Alternatives considered

- **Homebrew 全家桶(`temurin@17`、`android-commandlinetools` 等)** — 输在引入 brew 依赖(全新机器要先行安装)、cask/公式名随上游漂移,且与 Windows 脚本的"用户目录 + 官方归档直连"模型不对称;Adoptium/Google 直连 + `CV_JDK_ARCHIVE_URL` 镜像逃生保持了可控性。
- **Apple Silicon 上用 x86_64 镜像(与 Windows 默认一致)** — 被实测否决:x86_64 emulator 跑 x86_64 镜像在 Rosetta 下 HVF 初始化失败(`HVF Unknown error 0x4`),没有可用加速路径;arm64 镜像 + native aarch64 emulator 才是正解,Windows 侧维持 x86_64 不变。
- **把 macOS 引导也钉死 Flutter 3.47(与 Windows 一致)** — 放弃:桌面链已依赖 PATH Flutter(3.41.6),再下载一份 1GB+ 的重复 SDK 收益为零;改为一行 Kotlin 显式 apply 让仓库同时兼容两个 Flutter 版本。
- **只装 arm64 单 ABI 桥** — 物理设备是 arm64 但 Intel Mac 模拟器/CI 是 x86_64;双 ABI 只多一次 Go 编译(与 `build_android_debug.ps1` 一致),换来任一形态可跑。
- **在 Makefile 里内联全部逻辑** — Makefile 膨胀且脚本无法单独复用;入口薄、脚本承载流程与仓库既有风格一致。
- **让 `android-run` 强制每次重建模拟器** — 慢且打断"改代码→热重载"节奏;采用"物理设备优先,否则复用/启动常驻模拟器"。

## Consequences

- macOS 开发机一条 `make android-setup`(一次)+ `make android-run`(日常)即可进入 Android 调测;Ctrl-C 后模拟器保留,二次 attach 秒级进入。
- 需要维护与 Windows 脚本集的并行演化(NDK 版本、API 级别、镜像 ABI 现有多处出现,已互相链接到 [android_dev](../../features/android_dev.md))。
- 上游兼容性风险由探测 + 容忍兜底:NDK 宿主目录 glob、licenses 弃用容忍、repository2-3 归档解析;若上游再变更,失败点集中在 setup 对应步骤,gotcha 有现象与解法锚点。
- 验证(2026-08-29,Apple Silicon 实机):setup 真实安装(JDK 187MB/cmdline-tools/SDK 包/NDK r28c/arm64 镜像 + aarch64 emulator 替换)、`make android-bridge` 双 ABI 出 `.so`、`run_android.sh --boot-only` 启动模拟器至 `sys.boot_completed`、`flutter build apk --debug` 全量出包、APK 安装到模拟器并启动(Dart VM 起来,双 ABI `libremote_storage_bridge.so` 均在包内)。期间发现并修复:`macosx` host-os 标记、licenses 弃用、aarch64 emulator 缺 `package.xml`、Kotlin 插件显式 apply。提交前评审又修复 P0(Flutter manifest 解析 heredoc 覆盖 stdin,全新机器必死)与 P1(`yes |` 在 pipefail 下成功被误判),修复后单独实测 manifest 解析出 stable 3.47.2 arm64 归档 URL,setup 幂等重跑全绿(licenses 走真实 rc=0 分支、aarch64 跳过标记生效);完整评审叙事见 [PROJECT_GUIDE](../../PROJECT_GUIDE.md)。
