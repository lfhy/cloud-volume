# Android Dev — 开发环境、模拟器调测与 APK 构建(macOS 与 Windows)

仓库有 macOS 与 Windows 两套用户级 Android 工具链引导。macOS 侧提供模拟器调测回路(`make android-setup` → `make android-run`);Windows 侧出 ARM64 release APK。移动端通过打包的 c-shared FFI 库复用 Go 对象存储后端,同时隐藏桌面专属工作流。文件管理共享桌面运行时但独立维护 Android 呈现：固定紧凑列表、常驻搜索,桶/对象/回收站行遵循两态选择模型(浏览态行尾选择圆点、选中态头部变形 + 底部动作条,见 mobile_ui),桶行保留行尾 `…` 底部抽屉;隐藏网格/列表切换与挂载/卸载/打开挂载目录;进入桶/目录/回收站后二级顶栏提供返回按钮(加载和错误状态同样有效)。`ShadApp` 首页 route 内的根 `AnnotatedRegion<SystemUiOverlayStyle>` 在浅色主题下强制状态栏和导航栏使用深色图标，避免透明 edge-to-edge 系统栏吞掉时间、信号和电量；放在应用外层会被 route overlay 命中结果覆盖。

## 关键文件

- `scripts/setup_android_dev.ps1` - 默认用仓库根 `flutter_windows_3.47.0-stable.zip`(或 `-FlutterArchive`),Windows `tar.exe` 解压(Flutter 3.47 元数据目录 `Expand-Archive` 不可靠);本地压缩包缺失才回退在线 stable manifest。把 Flutter checkout 加入 Git `safe.directory`,持久化 `FLUTTER_ROOT`,然后装 Eclipse Temurin JDK 17、Android command-line tools、platform-tools、API 36、Build Tools 36.0.0、ARM64 Go 桥所需的 NDK 28.2.13676358;未跳过时还装 Android 36 Google APIs x86_64 模拟器镜像。持久化 `JAVA_HOME`、`ANDROID_HOME`、`ANDROID_SDK_ROOT`,把 Flutter、JDK、`cmdline-tools\latest\bin`(`sdkmanager`)、platform-tools(`adb`)、emulator 加入用户 PATH;随后接受 SDK 许可、把 Flutter 指向 SDK、`flutter doctor -v`,再跑 `flutter pub get` 与 `flutter test`(除非 `-SkipValidation`)。安装根可被 `-FlutterRoot`、`-AndroidSdkRoot`、`-JavaHome` 覆盖;`-SkipEmulator` 跳过镜像下载。
- `scripts/setup_android_dev.bat` - 双击启动器,从仓库根调 PowerShell 引导,交互使用时末尾暂停(除非 `CLOUD_VOLUME_NO_PAUSE=1`)。
- `scripts/setup_android_dev.sh` + `scripts/android_env.sh` - macOS 引导(镜像 `setup_android_dev.ps1`):复用 PATH 上的 Flutter(缺失时按 releases_macos manifest 装 stable 到 `~/dev/flutter`,`--flutter-archive`/`CV_FLUTTER_ARCHIVE_URL` 支持离线归档);Temurin JDK 17 装到 `~/dev/jdk-17`(已有 ≥17 JDK 的 `JAVA_HOME`/`java_home`/PATH 则复用);Android SDK 默认 `~/Library/Android/sdk`,装 cmdline-tools、platform-tools、API 36、Build Tools 36.0.0、NDK 28.2.13676358、emulator 与按主机 ABI(Apple Silicon→arm64-v8a,Intel→x86_64)的 Google APIs 镜像,并建 `cloud-volume` AVD(pixel_6)。Apple Silicon 额外两步:用 repository2-3 的 native aarch64 归档替换 sdkmanager 装的 x86_64 emulator(同一稳定版本;归档不带 `package.xml`,回填 sdkmanager 的那份供 avdmanager 识别),并确保 Rosetta 2(NDK 宿主工具链是 x86_64)。往 `~/.zshrc` 追加受保护的环境导出块(`--no-shellrc` 跳过),末尾 `flutter config --android-sdk`、`doctor -v`、`pub get`、`flutter test`(`--skip-emulator`/`--skip-validation` 分阶段跳过)。`android_env.sh` 是三个 Unix 脚本共享的解析 helper(Flutter/JDK/SDK 定位、Rosetta 与 NDK 探测),按 macOS 自带 bash 3.2 语法书写。
- `scripts/build_android_bridge.sh` - `build_android_bridge.ps1` 的 Unix 版:用 NDK 工具链为 `GOOS=android` 交叉编译 `./bridge` 到 `android/app/src/main/jniLibs/<abi>/libremote_storage_bridge.so`(ABI `arm64-v8a`/`x86_64`,`--sdk-root`/`--ndk-version`/`--api-level` 可覆盖),构建后删除生成的 C 头。
- `scripts/run_android.sh` - `make android-run` 的实现:先建双 ABI 桥(物理 ARM 设备与两种模拟器架构都能跑),无在线设备时创建并启动 `cloud-volume` AVD(窗口式;`--headless` 无窗、`--boot-only` 只等到 boot completed、`--skip-bridge` 跳过桥),模拟器日志写 `build/logs/android-emulator.log`;轮询 `sys.boot_completed` 后 `flutter run -d <serial>`。模拟器进程忽略 INT/QUIT/TERM,Ctrl-C 只结束 flutter 会话、模拟器留给下一次 attach;`CV_DEBUG_ADDR` 非空时自动 `adb forward` 并透传 dart-define;已连接且授权的物理设备优先于启动模拟器。
- `Makefile` - `android-setup`(引导)/`android-bridge`(双 ABI 桥)/`android-run`(调测回路)目标;Windows 主机上报错并指向对应 ps1 脚本。
- `scripts/build_android_bridge.ps1` - 用已装 NDK 为 `GOOS=android`、`GOARCH=arm64` 编译 `./bridge`,产物写入 `android/app/src/main/jniLibs/arm64-v8a/libremote_storage_bridge.so`;构建后删除生成的 C 头。
- `scripts/build_android.ps1` - 先建 Android 桥,再从 split 输出取 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`，复制为 `cloud-volume-release-arm64-v8a.apk`。
- `scripts/build_android_packages.sh` / `.github/workflows/release-desktop.yml` / `android/app/build.gradle.kts` - Linux CI 构建 ARM64 Go 桥与 split APK，注入签名密钥、核验包内 ABI 和签名，并将 APK 纳入 tag 发布；本地 `flutter run --release` 无签名环境时仍用 debug key。
- `android/` - Flutter Android runner。wrapper 用腾讯 Gradle 分发镜像,`settings.gradle.kts` / `build.gradle.kts` 优先 Aliyun 的 Google、Gradle-plugin、Central 仓库再官方源。
- `android/app/build.gradle.kts` / `android/app/src/main/kotlin/com/cloud/volume/MainActivity.kt` — Android `namespace` 与 `applicationId` 均为 `com.cloud.volume`;FrameTracker/输入法性能日志用它标识当前应用,不是远端存储地址。该 ID 同时决定安装升级身份与 `/data/user/0/<applicationId>` 私有沙箱及 `FileProvider` authority。旧 `cn.ihep.cloudvolume.remote_storage` 与新包可并存,新包不能读取或删除旧包私有数据;切换前通过既有远端配置备份保存账号配置,在新包首启时还原,未备份的账号需重新配置。决策理由见 [Android 应用标识迁移](../notes/implemented/architecture/2026-08-31-android-application-id.md)。
- `bridge/dispatch_mobile.go` / `bridge/dispatch.go` / `go/config/paths.go` - Android 启动经 `set_app_data_root` 把 Flutter 的 application-support 目录传给原生桥,配置与缓存留在 Android 应用存储内而非无效的桌面 home。
- `go/config/paths_mobile_test.go` - 钉住 `SetAppDataRoot` 覆盖与空路径拒绝语义。
- `lib/bridge/remote_storage_bridge.dart` - Android 打开打包的 `libremote_storage_bridge.so` 并在配置调用前初始化该 app-data root。
- `lib/app/app_entry_io.dart` / `lib/app/remote_storage_app.dart` / `lib/pages/app_bootstrap_page.dart` / `lib/services/remote_storage_api_desktop.dart` / `remote_storage_gateway.dart` - 把 `desktop_multi_window`、`window_manager`、桌面 chrome、挂载、本地目录同步、WebDAV 启动挡在移动启动外,暴露其余移动能力。`remote_storage_app.dart` 在首页 route 内声明浅色 Android 系统栏样式；Android 模态会以嵌套 region 临时覆盖它。
- `third_party/super_native_extensions` / `third_party/irondash_engine_context` / `lib/services/desktop_file_transfer_service_io.dart` / `lib/widgets/file_transfer_clipboard_region.dart` / `lib/pages/file_manager_page.dart` / `file_manager_page_presentation.dart` / `mobile_file_manager_presentation.dart` / `mobile_file_manager_page.dart` / `lib/widgets/file_manager_object_browser_mobile.dart` - 桌面保留 Git 恢复的原生拖放与 file URI 剪贴板实现,仅移除 Android 插件注册。Android 通过 `MobileFileManagerPage` 复用 `FileManagerWorkspace` 的数据、加载、mutation 与 Back 栈，但由 `mobile_file_manager_presentation.dart` 维护移动页头/搜索/操作行；桶和对象浏览器以底部抽屉展示适用操作，不创建 `DropRegion`,继续用选择器上传。
- `lib/services/file_access_service_io.dart` / `file_access_service_preview_io.dart` / `file_access_service_downloads_io.dart` / `file_access_paths_io.dart` / `local_file_opener_io.dart` - 桌面用 `file_selector` 获得可写、用户可改名的保存路径；Android 预览下载复用 `<cacheDir>/files/<bucket>/<key>` 的已校验缓存，`cloud_volume/external_file_opener` 只在用户选择外部应用打开时复制到受限 `FileProvider` cache 路径并以 `ACTION_VIEW` chooser 交接。Android 预览不使用系统另存为。完整预览数据流见 [file_actions](file_actions.md)。
- `android/app/src/main/kotlin/com/cloud/volume/AndroidExternalFileOpener.kt` / `android/app/src/main/res/xml/external_open_paths.xml` / `AndroidManifest.xml` - 原生文件交接边界：provider 只暴露 `cache/external-open/` 的副本，外部应用拿到短期 `content://` 读授权并由 `ACTION_VIEW` chooser 打开。
- `README.md` - 记录引导、移动能力、限制与 APK 构建命令。

## GitHub Actions CI 发布

`vX.Y.Z` tag 推送会触发 `.github/workflows/release-desktop.yml` 的 `android` job。Ubuntu runner 配置 Java 17、Go、Flutter 3.47.0、Android API 36 / Build Tools 36.0.0 / NDK 28.2.13676358；`scripts/build_android_packages.sh` 先构建 ARM64 Go 桥，再以 `--split-per-abi --target-platform android-arm64` 只取 `app-arm64-v8a-release.apk`。脚本校验包内只有 ARM64 原生库、含 `libremote_storage_bridge.so` 且通过 `apksigner verify`，上传 `yunjuan-android-arm64-v<X.Y.Z>.apk`。发布 job 仅在 Android job 成功时运行；其他平台的原有部分发布语义不变。设计取舍见 [Agent Note](../notes/implemented/process/2026-09-29-android-ci-release-signing.md)。

仅测试 Android CI 构建时，在 GitHub Actions 的 `release-desktop` 页面点 **Run workflow**，选择 `main`、勾选 **Build only the signed Android APK**，保留测试版本 `0.0.0` 后运行。此模式只启动 `android` job，其它平台与 `publish` 全部跳过；签名 APK 留在该次 run 的 `yunjuan-android-arm64` artifact，不创建 GitHub Release，也不要把 `v0.0.0` 测试包分发给用户。正式 tag 推送仍执行完整发布矩阵。

### 首次配置 Repository secrets

打开仓库 [Settings → Secrets and variables → Actions](https://github.com/lfhy/cloud-volume/settings/secrets/actions)，逐个点 **New repository secret**，建立以下四项（不要把密钥或密码贴进 issue、聊天或提交）：

| 名称 | 填入的值 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | 完整 keystore 文件的单行 Base64 文本，不是文件路径。 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 的 store 密码。 |
| `ANDROID_KEY_ALIAS` | keystore 内用于签名的 key alias。 |
| `ANDROID_KEY_PASSWORD` | 该 alias 的 key 密码；若与 store 密码相同，填相同值。 |

先确定签名证书：若已有向用户分发的 `com.cloud.volume` APK，用 Android SDK 的 `apksigner verify --print-certs <旧包.apk>` 记下 SHA-256 指纹，再用 `keytool -list -v -keystore <原密钥库> -alias <alias>` 核对。要覆盖升级，必须沿用同一证书；新的正式密钥无法覆盖旧的 debug-key 安装。若没有可复用的正式密钥，可在安全位置执行下例生成新密钥（交互输入密码，不把密码写进命令历史）：

```bash
keytool -genkeypair -storetype PKCS12 -keystore "$HOME/yunjuan-release.p12" \
  -alias cloud-volume -keyalg RSA -keysize 3072 -validity 10000
```

将密钥文件编码后粘贴到 `ANDROID_KEYSTORE_BASE64`：macOS 用 `base64 -i "$HOME/yunjuan-release.p12" | tr -d '\n' | pbcopy`，Windows PowerShell 用 `[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\path\yunjuan-release.p12')) | Set-Clipboard`。粘贴完成后清空剪贴板；另外三项填实际密码与 alias。把原密钥库和密码在仓库之外安全备份：GitHub Secrets 不能读回，遗失证书会影响后续升级；仅更换密码不能撤销已泄露的私钥。

CI 在缺少任一 secret、Base64 无效或签名失败时直接失败，不会用 debug key 发布。`android/app/build.gradle.kts` 仅在全部签名环境变量都未设置时保留本地 `flutter run --release` 的 debug-key 回退；只设一部分也会失败。本地 `scripts/build_android_packages.sh` 同样要求全部四项签名环境变量（其中 `ANDROID_KEYSTORE_FILE` 是解码后的绝对路径）。正式密钥与旧 APK 证书不同的用户，应先通过应用内远端配置备份，再卸载旧包并安装新包；卸载会清除该包的私有数据。

## Gotchas

- release APK(Windows `build_android.ps1` 从 split 输出只取 `app-arm64-v8a-release.apk`;CI 同样只发布 ARM64);macOS 调试回路(`run_android.sh`)构建 arm64-v8a + x86_64 双 ABI 桥,物理设备与两种模拟器架构都能跑。32 位 ARM 仍不支持。
- NDK 的 macOS 宿主工具链目录是 `darwin-x86_64`,Apple Silicon 靠 Rosetta 2 运行;`android_env.sh` 的 `cv_ensure_rosetta` 尝试 `softwareupdate --install-rosetta --agree-to-license`,失败时按该命令手动安装。宿主目录按 `darwin-*` glob 探测,上游若发布 native arm64 工具链无需改脚本。
- **Apple Silicon 模拟器架构(binding gotcha):** legacy sdkmanager 走 repository2-1,其 macOS emulator 归档只有 x86_64;该构建跑 arm64 镜像直接 FATAL(launcher 把 Rosetta 下的 host 判成 x86_64),跑 x86_64 镜像则 `HVF Unknown error 0x4`(Rosetta 进程无法用 HVF 虚拟化 x86_64 guest)。正解是 repository2-3 的同版本 `emulator-darwin_aarch64` 归档(setup 自动替换),配 arm64-v8a 镜像走 native HVF;aarch64 归档不带 `package.xml`,必须回填 sdkmanager 的那份,否则 avdmanager 建 AVD 时报 "emulator package must be installed"。
- 上游兼容性两处:Android repository XML 的 macOS host-os 标记是 `macosx`(旧归档为 `mac`);cmdline-tools 23 弃用 `sdkmanager --licenses`("no longer needed")且首次调用可能非零退出,setup 按"重试一次 + 输出含 no longer needed 即通过"容忍。flutter doctor 的 license 探针与 cmdline-tools 23 不兼容,会一直显示 "license status unknown"——license 文件已写入 `licenses/`,构建不受影响。
- **dl.google.com 不可达时的镜像引导变体(2026-09-15 实测)**:若 `dl.google.com` 超时而 `storage.googleapis.com`/adoptium/pub.dev 可达,`setup_android_dev.sh` 会在 cmdline-tools 一步失败;JDK/Flutter 两节可照跑,SDK 改从腾讯云镜像 `https://mirrors.cloud.tencent.com/AndroidSDK/` 手动铺:解析其 `repository2-1.xml`(元素命名空间 `.../repository2/01`,`archives→archive→complete` 取 URL;平台包无 host-os 视为任意宿主)拿归档名,解压到 `cmdline-tools/latest`、`platform-tools`、`platforms/android-36`(`platform-36_r02.zip`)、`build-tools/36.0.0`、`ndk/28.2.13676358`(`android-ndk-r28c-darwin.zip`),手写 `licenses/android-sdk-license`(三行历史哈希)——Gradle/AGP 只认目录布局与 license 文件,不需要 sdkmanager 本体。`softwareupdate --install-rosetta --agree-to-license` 可免 sudo 装好 Rosetta 2;NDK r28c 宿主工具链仍是 `darwin-x86_64`。Gradle 侧无需改动(wrapper 已指腾讯镜像、Maven 走 Aliyun 仓),`flutter build apk` 首跑会按需自动补装 SDK Platform 35 与 CMake 3.22.1。macOS 引导装的是当日 stable(实测 3.47.4),`pub get` 会把 lock 内 SDK 钉住的 test_api/matcher/meta/vector_math/intl 升版(仓库锁由 Windows 3.47.0 生成)——本地构建/测试可照用,收尾 `git checkout pubspec.lock` 恢复,不要提交漂移;只建 arm64 桥时,`--split-per-abi` 三个产物中仅 `app-arm64-v8a-release.apk` 含桥,其余 ABI 不可安装使用(与 Windows 出包只发 arm64 一致)。
- `android/app/build.gradle.kts` 显式 apply `org.jetbrains.kotlin.android`(版本钉在 `settings.gradle.kts` 2.4.0):Flutter 3.47 的 flutter-gradle-plugin 会自动补 Kotlin 插件,更早版本(如 3.41)不会,缺了它 `kotlin { compilerOptions { jvmTarget } }` 块解析失败。
- 模拟器镜像按主机 CPU 选择(Apple Silicon → arm64-v8a + native aarch64 emulator;Intel → x86_64),与 NDK 桥的 ABI 无关——两个 ABI 的 `.so` 都会打进 debug APK。

**Known P2/P3 (review 2026-08-29):** 提交前评审(叙事见 [PROJECT_GUIDE](../PROJECT_GUIDE.md))发现并同批修复:P0 Flutter manifest 解析 heredoc 覆盖管道 stdin(改为先落盘再传 argv)、P1 `yes | sdkmanager --licenses` 在 pipefail 下成功被误判(改有限答案文件)、P2 boot 等待对单次 adb 抖动零容忍(加 `|| true`)、P3 android-setup 缺 Windows gating、P3 aarch64 emulator 每次重跑重复下载 400MB(加跳过标记)、P3 替换前先解压后删旧树。仍开放的 P3:回填的 `package.xml` 版本不与 repository2-3 归档校验,两 channel 漂移时 `sdkmanager` 升级可能把 emulator 换回 x86_64;`~/.zshrc` 块在换 `--sdk-root`/`--java-home` 重跑时不刷新,首跑 `--no-shellrc` 装了 Flutter 次跑补写块会漏 flutter PATH 项;`run_android.sh` 的 AVD 名 grep 把 `--avd` 参数当正则用(仅误报向)。

**Known P2/P3 (review 2026-09-29):** P2 开放：`apksigner verify` 只验证签名有效，不验证与上一正式版证书的 SHA-256 一致；首次配置时按上文核对旧包，后续可把首次正式证书指纹固定为 CI 门禁。P3 已修复：临时 keystore 解码前设 `umask 077`，限制 runner 上的文件权限。
- Go 桥是大体积静态工件,被 Git 有意忽略。每次 APK 构建前在构建机上跑 `scripts/build_android.ps1`。
- `third_party/super_native_extensions` 与 `third_party/irondash_engine_context` 是 vendored 的桌面专属插件 fork。其 Android 注册被移除,因为 CargoKit 的 Gradle 脚本与 Gradle 9 不兼容;CargoKit 支持该构建前不要恢复那些声明。桌面拖放与 file URI 剪贴板保持可用;Android 用 `file_picker` 上传,不创建原生 drop region。
- 引导仍从 Adoptium 与 Google Android 服务下载 JDK/SDK 包;封锁这些端点的网络会阻止安装,Flutter 本身可从仓库根压缩包离线引导。脚本不做部分安装清理,不破坏性替换已有目录。
- 完成后打开新 PowerShell 窗口,持久化的用户 PATH 才对交互 shell 可见。
- `sdkmanager.bat` 需要 `JAVA_HOME`(且其 `bin` 在 `PATH`),即使 JDK 文件已在。中断的引导可能留下 SDK 已装但 `sdkmanager --version` 报缺 Java——先恢复 `JAVA_HOME`、`ANDROID_HOME`、`ANDROID_SDK_ROOT`、`FLUTTER_ROOT` 与 Flutter/JDK/platform-tools 的 PATH 再重跑 setup。
