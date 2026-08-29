# Android Dev — 开发环境与 ARM64 APK 构建(Windows)

仓库有用户级 Android 工具链引导与 ARM64 APK 构建路径。移动端通过打包的 c-shared FFI 库复用 Go 对象存储后端,同时隐藏桌面专属工作流。

## 关键文件

- `scripts/setup_android_dev.ps1` - 默认用仓库根 `flutter_windows_3.47.0-stable.zip`(或 `-FlutterArchive`),Windows `tar.exe` 解压(Flutter 3.47 元数据目录 `Expand-Archive` 不可靠);本地压缩包缺失才回退在线 stable manifest。把 Flutter checkout 加入 Git `safe.directory`,持久化 `FLUTTER_ROOT`,然后装 Eclipse Temurin JDK 17、Android command-line tools、platform-tools、API 36、Build Tools 36.0.0、ARM64 Go 桥所需的 NDK 28.2.13676358;未跳过时还装 Android 36 Google APIs x86_64 模拟器镜像。持久化 `JAVA_HOME`、`ANDROID_HOME`、`ANDROID_SDK_ROOT`,把 Flutter、JDK、`cmdline-tools\latest\bin`(`sdkmanager`)、platform-tools(`adb`)、emulator 加入用户 PATH;随后接受 SDK 许可、把 Flutter 指向 SDK、`flutter doctor -v`,再跑 `flutter pub get` 与 `flutter test`(除非 `-SkipValidation`)。安装根可被 `-FlutterRoot`、`-AndroidSdkRoot`、`-JavaHome` 覆盖;`-SkipEmulator` 跳过镜像下载。
- `scripts/setup_android_dev.bat` - 双击启动器,从仓库根调 PowerShell 引导,交互使用时末尾暂停(除非 `CLOUD_VOLUME_NO_PAUSE=1`)。
- `scripts/build_android_bridge.ps1` - 用已装 NDK 为 `GOOS=android`、`GOARCH=arm64` 编译 `./bridge`,产物写入 `android/app/src/main/jniLibs/arm64-v8a/libremote_storage_bridge.so`;构建后删除生成的 C 头。
- `scripts/build_android.ps1` - 先建 Android 桥,再出 ARM64 Flutter release APK 到 `build/app/outputs/flutter-apk/app-release.apk`。
- `android/` - Flutter Android runner。wrapper 用腾讯 Gradle 分发镜像,`settings.gradle.kts` / `build.gradle.kts` 优先 Aliyun 的 Google、Gradle-plugin、Central 仓库再官方源。
- `bridge/dispatch_mobile.go` / `bridge/dispatch.go` / `go/config/paths.go` - Android 启动经 `set_app_data_root` 把 Flutter 的 application-support 目录传给原生桥,配置与缓存留在 Android 应用存储内而非无效的桌面 home。
- `go/config/paths_mobile_test.go` - 钉住 `SetAppDataRoot` 覆盖与空路径拒绝语义。
- `lib/bridge/remote_storage_bridge.dart` - Android 打开打包的 `libremote_storage_bridge.so` 并在配置调用前初始化该 app-data root。
- `lib/app/app_entry_io.dart` / `lib/app/remote_storage_app.dart` / `lib/pages/app_bootstrap_page.dart` / `lib/services/remote_storage_api_desktop.dart` / `remote_storage_gateway.dart` - 把 `desktop_multi_window`、`window_manager`、桌面 chrome、挂载、外部文件打开、本地目录同步、WebDAV 启动挡在移动启动外,暴露其余移动能力。
- `third_party/super_native_extensions` / `third_party/irondash_engine_context` / `lib/services/desktop_file_transfer_service_io.dart` / `lib/widgets/file_transfer_clipboard_region.dart` / `lib/pages/file_manager_page.dart` - 桌面保留 Git 恢复的原生拖放与 file URI 剪贴板实现,仅移除 Android 插件注册。`FileManagerPage._buildFileTransferSurface` 是 Android/iOS 边界:移动端返回未包裹内容,绝不创建 `DropRegion`,继续用选择器上传。
- `lib/services/file_access_service_io.dart` / `file_access_service_downloads_io.dart` - 桌面用 `file_selector` 获得可写、用户可改名的保存路径而不在 Dart 缓冲下载;Android 持续流入应用临时目录,直到单独的 Storage Access Framework 实现落地。
- `README.md` - 记录引导、移动能力、限制与 APK 构建命令。

## Gotchas

- 当前只打包 `android-arm64`。发布 x86_64 模拟器或 32 位 ARM APK 前先加独立 NDK 桥构建。
- Go 桥是大体积静态工件,被 Git 有意忽略。每次 APK 构建前在构建机上跑 `scripts/build_android.ps1`。
- `third_party/super_native_extensions` 与 `third_party/irondash_engine_context` 是 vendored 的桌面专属插件 fork。其 Android 注册被移除,因为 CargoKit 的 Gradle 脚本与 Gradle 9 不兼容;CargoKit 支持该构建前不要恢复那些声明。桌面拖放与 file URI 剪贴板保持可用;Android 用 `file_picker` 上传,不创建原生 drop region。
- 引导仍从 Adoptium 与 Google Android 服务下载 JDK/SDK 包;封锁这些端点的网络会阻止安装,Flutter 本身可从仓库根压缩包离线引导。脚本不做部分安装清理,不破坏性替换已有目录。
- 完成后打开新 PowerShell 窗口,持久化的用户 PATH 才对交互 shell 可见。
- `sdkmanager.bat` 需要 `JAVA_HOME`(且其 `bin` 在 `PATH`),即使 JDK 文件已在。中断的引导可能留下 SDK 已装但 `sdkmanager --version` 报缺 Java——先恢复 `JAVA_HOME`、`ANDROID_HOME`、`ANDROID_SDK_ROOT`、`FLUTTER_ROOT` 与 Flutter/JDK/platform-tools 的 PATH 再重跑 setup。
