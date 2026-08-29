# Windows Dev — 本地开发工作流

Windows 开发有两个脚本:新机依赖引导一个,依赖就绪后的运行/构建一个。运行/构建细则也见 [DEVELOPMENT_GUIDE](../DEVELOPMENT_GUIDE.md)。

## 关键文件

- `scripts/setup_windows_dev.bat` - 双击启动器:切到仓库根,`powershell -NoProfile -ExecutionPolicy Bypass` 调 `setup_windows_dev.ps1`,转发参数,报告成功/失败,末尾为双击用户暂停(`CLOUD_VOLUME_NO_PAUSE=1` 跳过)。
- `scripts/setup_windows_dev.ps1` - 新机引导。用 `winget` 安装/校验 Git、Go、Visual Studio 2022 Build Tools、MSYS2,直连安装器兜底(VS Build Tools 与 MSYS2 可完全脱离 winget;**Git 与 Go 仍需要 winget 或预先安装**才能走完后续步骤)。还经官方 `rustup-init` 装 MSVC Rust 工具链,把 `$HOME\.cargo\bin` 加进用户 `PATH` 并确保匹配 target。架构检测尊重 `PROCESSOR_ARCHITEW6432` 使模拟 PowerShell 仍见原生 OS。x64 装 UCRT64 `mingw-w64-ucrt-x86_64-gcc`;ARM64 装 CLANGARM64 `mingw-w64-clang-aarch64-clang` 与 VS `Microsoft.VisualStudio.Component.VC.Tools.ARM64` 组件(必要时修改既有 Build Tools 安装)。Go MSI 回退也用原生 `amd64`/`arm64` 工件。设置 `FLUTTER_ROOT`、架构匹配的 `BRIDGE_CC`/`BRIDGE_CXX`、用户 `PATH`、默认 `GOPROXY=https://goproxy.cn,direct`(保留自定义代理)。Developer Mode 不可用只警告;探测中国 Flutter 镜像失败才回退官方源;检查原生退出码。可选参数:`-FlutterRoot`、`-MsysRoot`、`-SkipWingetInstall`、`-SkipFlutterClone`、`-SkipMsysPackages`、`-SkipDoctor`、`-ValidateProject`。
- `scripts/run_windows.ps1` - 正典 Windows 本地运行/构建助手。检测原生 x64/ARM64,解析 Flutter、Go、Rustup,x64 选 UCRT64 GCC/G++,ARM64 选 CLANGARM64 Clang/Clang++,并先校验各编译器 `-dumpmachine` 再启用 cgo。ARM64 上必须有 Rustup,CargoKit 插件(如 `super_native_extensions`)才能本地构建而不是下载 GitHub Release 工件;CargoKit verbose 日志暴露底层失败而不是只报 MSB8066。错误架构的陈旧 `BRIDGE_CC` 跳过;显式传入的不兼容编译器立即失败并给聚焦错误。设置 `GOOS=windows`、原生 `GOARCH`、`CGO_ENABLED`、`CC`/`CXX`、构建桥接、运行/构建 Flutter。Release 输出动态用 `build/windows/x64/...` 或 `build/windows/arm64/...`,返回成功前校验 `cloud-volume.exe`、`cloud-volume-app.exe`、崩溃报告器与更新器。Developer Mode 缺失仅警告。Build 模式嵌入 `APP_VERSION_LABEL`,run 模式默认 `dev`。Flutter/编译器缺失快速失败,不代下载安装。
- `scripts/run_windows_debug.bat` - 双击 debug 运行启动器:先建桥接 DLL 再 `flutter run -d windows`。
- `scripts/build_windows.bat` - 双击 release 构建启动器:调 `run_windows.ps1 -Build`,检测 x64/ARM64(含模拟 shell),打开匹配的 `build/windows/<x64|arm64>/runner/Release/`。
- `scripts/build_windows_installer.ps1` - 经 Inno Setup 6 从架构匹配的 Flutter release bundle 构建 `yunjuan-windows-<x64|arm64>-installer.exe`;架构指令传 `x64compatible` 或 `arm64`,版本用 `git describe`,除非给 `-Version`。
- `scripts/build_windows_installer.bat` - 双击打包启动器,完成后暂停。
- `README.md` - Windows 开发文档:引导、架构工具链、运行/构建启动器、Developer Mode、Go/Flutter 镜像。

## Gotchas

- **ARM64 cgo 必须用脚本选择的 CLANGARM64 编译器。** `gcc_arm64.S` 再报未知 `stp`/`ldp`/`blr` 指令时,检查打印的编译器 target:必须是 `aarch64`/`arm64`,不是 `x86_64`。`-BridgeCc`/`-BridgeCxx` 传入的 target 与原生架构不匹配时被有意拒绝。
- **Flutter Windows 的 VS 就绪不止 workload ID:** ARM64 主机需要 `Microsoft.VisualStudio.Component.VC.Tools.ARM64` 与 `MSBuild\Microsoft\VC\*\Platforms\ARM64`。setup 脚本校验该平台目录并等 VS setup modify 完成;run 脚本缺失时提前失败并给精确安装命令。
- `go/mount/cloud_files_*_windows.go` 的 cgo 源**不得**硬编码 `-D_AMD64_`——ARM64 上会强制 x64 `windows.h` 内在函数(`+D`、`=@ccc`)并重定义 `CONTEXT`。用架构特定的 `#cgo amd64 CFLAGS` / `#cgo arm64 CFLAGS`。
- **`Resolve-Executable` 不得把裸命令名当文件系统路径。** 仓库有顶层 `go/` 目录,`Test-Path` 解析 `go` 会返回该目录,之后 `& $go build` 报「无法识别 C:\...\cloud-volume\go」。裸名只走 `Get-Command`/显式候选。
- 部分 Windows ARM 主机上 PowerShell 调用操作符(`& clang.exe -dumpmachine`)即使编译器正常也返回空输出。run 脚本经 `System.Diagnostics.ProcessStartInfo` 探测编译器,已知 `C:\msys64\clangarm64\bin\clang(.exe|++.exe)` 路径优先于指向 UCRT64 gcc 的陈旧用户 `BRIDGE_CC`,成功匹配后回写用户 `BRIDGE_CC`/`BRIDGE_CXX`。
- **`super_native_extensions` 用 CargoKit。** 无 Rustup 时 CargoKit 先从 GitHub Releases 下载签名的 `aarch64-pc-windows-msvc` 二进制;该 ARM64 主机上 Dart HTTP client 即使 PowerShell 能达同 URL 也超时,MSBuild 只报 MSB8066。setup 装 Rustup,run 脚本在 Flutter 启动前把 `$HOME\.cargo\bin` 加进 PATH,CargoKit 走内置本地构建路径。
- 直连下载用重试 `Invoke-WebRequest`,然后 `curl.exe -L --ssl-no-revoke`——后者处理吊销服务器离线导致证书吊销检查失败的机器。
- VS Build Tools 安装器退出码 `3010` = 成功但需重启;脚本接受并继续。
- Flutter 首次引导可能让 `bin/cache/dart-sdk` 不完整无 `dart.exe`;脚本检测该状态并从 `FLUTTER_STORAGE_BASE_URL` 为当前引擎版本下载 `dart-sdk-windows-x64.zip` 再调 `flutter.bat`。
- Flutter 若从提权进程克隆/安装,Git 可能以 `detected dubious ownership` 拒绝(目录属 `BUILTIN/Administrators`);setup 与 run 脚本都把解析出的 Flutter root 加入当前用户全局 Git `safe.directory`。
- Flutter Windows 插件可能需要符号链接支持。两个脚本检查 `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock\AllowDevelopmentWithoutDevLicense`;管理员时尝试设 1,否则把 Developer Mode 路径作警告不阻塞。
- `setup_windows_dev.ps1` 默认不跑完整应用构建;`-ValidateProject` 在依赖装完后调 `run_windows.ps1 -Build`。
- setup 写入用户环境变量与 PATH 后,交互使用 `run_windows.ps1` 前打开新 PowerShell 窗口。
