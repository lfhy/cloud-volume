# Development Guide — 构建、验证、提交与评审

## 构建产物

- 不要把编译产物或构建中间物写到仓库根目录。本地 Go / Flutter 构建产物统一路由到 `bin/`、`build/` 或工具管理的构建目录。
- 从仓库根做临时 Go 冒烟验证时,不要裸跑 `go build .`;手动桥接冒烟用 `go build -o bin/...`,临时产物用完即删。
- Windows 上构建桥接动态库:`go build -buildmode=c-shared -o bin/bridge/remote_storage_bridge.dll ./bridge`,需要 `CGO_ENABLED=1` 和 MinGW 工具链(如 MSYS2 UCRT64,通过 `BRIDGE_CC`/`BRIDGE_CXX` 选择)。

## 启动命令(按平台)

- **macOS(标准):** `make run`。它先跑 `make bridge` 把 `./bridge` 构建为 `bin/bridge/libremote_storage_bridge.dylib`,再用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter run -d macos` 启动。macOS 应用必须走 Go 绑定工作流,不要裸 `flutter run -d macos`。
- **Windows(标准):** `scripts/run_windows.ps1`。它解析 Flutter 与 MSYS2 MinGW 工具链、构建桥接 DLL,再 `flutter run -d windows`。`.\run_windows.ps1 -Build` 构建发布包。不要裸 `flutter run -d windows`。
- **Android:** Windows 出包用 `scripts/build_android.ps1`(先建 ARM64 桥接 `libremote_storage_bridge.so` 再出 release APK),环境引导用 `scripts/setup_android_dev.ps1`。macOS 调测:一次 `make android-setup` 引导 JDK/SDK/NDK/模拟器与 `cloud-volume` AVD,日常 `make android-run`(双 ABI 桥 + 无设备时启动模拟器 + `flutter run`)。细则见 [android_dev](features/android_dev.md)。
- 验证集成启动时优先用上述脚本,保证桥接二进制与工具链路径都正确。

## 验证

- 每个有意义的重构批次之后,先跑最窄的有效验证。
- 收尾前跑 `go test ./...` 和 `flutter analyze`,除非用户明确要求其它验证范围。
- 不要用截图作为冒烟验证证据。
- 默认不跑本地冒烟;实现完成后应用级验证交给用户,除非用户明确要求你跑。
- 文档/规范类改动:跑 `make check-docs` 和 `git diff --check`,不需要跑测试。

## Git 工作流

- 完成请求的实现并成功验证后,创建常规非 amended 提交,除非用户明确说不提交。
- 提交不包含编译产物或临时构建物。
- 每次新增功能,同一变更集内更新 `README.md` 再提交。
- 与 upcoming release 相关的改动在 `CHANGELOG.md` 的 `## Unreleased` 下维护草稿。
- **决策记录(binding):** 非平凡变更在同一变更集中新增或更新至少一条 [Agent Note](notes/README.md)(为什么、替代方案、后果、验证);纯机械/局部改动豁免。

## 提交前强制评审(binding)

- 每个代码改动落地 `main` 前必须通过 P0/P1 级子代理评审。P0/P1 发现视为 blocking;P2/P3 可延后,但发现与解决链接必须记录在对应特性的 Code Map 条目(现为 `docs/features/*.md` 的「Known P2/P3」小节)——完整叙事按性质分流:改变了设计决策的写成 [Agent Note](notes/README.md),纯过程叙事进 [PROJECT_GUIDE.md](PROJECT_GUIDE.md)(规则见 [DOC_STANDARDS.md](DOC_STANDARDS.md))。
- 评审子代理只需要 `git show` / `git diff` 暴露的内容加上它点名要看的周边文件;`fork none`,给一份简短 brief:提交哈希、动机/修复的 bug、要考察的具体风险轴。
- 改变范围的评审发现(新不变式、新文件加入特性)必须并入对应 `features/*.md` 后,解决提交才能落地。历史发现与其解决方式记录在该特性的 `**Known P2/P3 (review YYYY-MM-DD):**` 块。
- 评审子代理自身可以委派更深的审计(如 `post_commit_review`),但主会话负责 triage 输出并推进解决提交。

## 调试端点

`make run` 导出 `CV_DEBUG_ADDR`(默认 `127.0.0.1:8765`),桥接在首次调用时惰性启动仅 loopback 的 HTTP 监听。端点清单、WebSocket 推送协议与 `NotifyTaskChanged` 覆盖率等 binding 见 [remote_tasks](features/remote_tasks.md#调试端点binding)。`CV_DEBUG_ADDR=`(空)禁用监听;绑定 0.0.0.0 或暴露到 localhost 之外是禁止的。

## 新存储后端

用户要求新增存储类型(FTP、SFTP 或任何新远端 provider)时,按 [AddingStorageBackends.md](AddingStorageBackends.md) 的五层改动指南(Go config → Go backend → bridge → Dart model → Dart UI)执行。
