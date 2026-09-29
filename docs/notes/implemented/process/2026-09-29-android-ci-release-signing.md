# Agent Note: Android 签名 APK 纳入统一 tag 发布

Status: implemented

## Problem

Android 构建原来只在本地生成以 debug key 签名的 APK，tag 发布没有 Android 产物。发布可安装、可持续升级的正式 APK 需要在 CI 上构建 Go FFI 桥、管理私有签名密钥，并避免缺密钥时把 debug 签名包误发给用户。统一 release 工作流的 `publish` 使用 `always()`，单纯新增一个依赖不会阻止缺失 Android 包的部分发布。

## Decision

在现有 `.github/workflows/release-desktop.yml` 加 Android ARM64 job，并让 tag 发布显式要求该 job 成功。Ubuntu runner 复用 Unix NDK 桥脚本，`scripts/build_android_packages.sh` 只取 ARM64 split APK，检查包内 FFI 桥、ABI 和签名后交给既有 artifact → release 流程。签名密钥以四项 Repository secrets 提供，Base64 文件只在 runner 临时目录解码；打包入口缺签名环境即失败。Gradle 在四项签名环境齐全时使用正式证书，部分配置立即报错；全部未设置时保留本地 `flutter run --release` 的 debug 签名便捷性，但该路径不能通过发布脚本。

`workflow_dispatch` 另提供 `android_only` 布尔输入与 `android_version`（默认 `0.0.0`），在普通分支手动验证时只运行 Android job，跳过其它平台和发布。tag push 的输入为空，保持完整发布矩阵。这样不必创建临时 semver 分支或 tag，也不会因测试构建意外创建公开 Release。

## Alternatives considered

- **提交密钥库或在 CI 使用 debug key** — 私钥进入 Git 历史无法安全撤销，debug 证书也不是稳定的正式分发身份，放弃。
- **只指定 `--target-platform android-arm64` 构建通用 APK** — 实测插件的其他 ABI 原生库仍会进入通用包；改为只发布 ARM64 split APK，并核查其内容。
- **另建独立发布 workflow** — 会与现有 tag release 并发上传、增加跨工作流协调；保留单一发布入口。
- **让 Android 失败后继续发布其它产物** — 会产生无 Android 下载项的同版本 release；Android 成为必要发布门禁，但其它既有 job 的部分发布语义暂不扩大修改。
- **为测试创建 `v0.0.0` 临时分支或 tag** — 分支会污染远端命名空间，tag 还会触发正式发布；手动输入版本与 job gate 更直接。

## Consequences

必须先设置并安全备份正式签名密钥，tag 发布才能完成；相同 `com.cloud.volume` 包名换证书不能覆盖升级既有安装，需通过配置备份和重装迁移。CI 的密钥只在临时文件与构建进程中使用，APK 按 tag 版本命名，Flutter split 的 versionCode 带 ABI 偏移；版本号与 build number 由发布 workflow 传入。

本地以一次性测试密钥实际构建 ARM64 split APK，核对只有 ARM64 原生库、含 Go 桥、`apksigner verify --print-certs` 显示该证书；`actionlint`、`bash -n`、文档门禁与仓库 Go/Flutter 检查在提交前执行。真正的 GitHub-hosted runner 与用户密钥要待 Repository secrets 配置后由 tag 发布验证。
