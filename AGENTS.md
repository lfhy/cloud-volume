# Repository Guidelines

动手前(探索、搜索、修改、构建、测试)先读 [docs/AGENT_GUIDE.md](docs/AGENT_GUIDE.md) 的必读顺序;特性正典在 [docs/CODE_MAP.md](docs/CODE_MAP.md) → `docs/features/*.md`。

**反膨胀规则(binding):** 本文件只放每次会话都必须看见的常备规则,每条尽量 1–3 行并链接归属文档。新内容一律写进 `docs/` 而不是扩充本文件;文档分层、归属与字数预算见 [docs/DOC_STANDARDS.md](docs/DOC_STANDARDS.md),`make check-docs` 必须通过。

## `lib` And `go` Structure Rules

- `lib`、`go`、`bridge`、`macos/Runner` 下的手写代码文件不超过 500 行;接近上限时先按特性/职责拆分再加逻辑。生成物(`.dart_tool`、`build`、`bin`、`macos/Flutter/ephemeral`)豁免。
- 上述范围内每个手写文件至少一条有意义注释;优先文件级注释说明文件职责,非显而易见逻辑处加短节注释。

## Flutter Frontend Organization

- 按类型优先、再按特性组织:`lib/app`、`lib/pages`、`lib/widgets`、`lib/services`、`lib/state`、`lib/utils`、`lib/theme`、`lib/bridge`、`lib/models`。入口文件保持薄,只做模块装配。
- **Hover(binding):** 可点击行/tile/卡/侧栏项的 hover 必须是持有 `_hovered` 的独立 `StatefulWidget`,视觉仅中性背景洗色;完整规则与正典实现见 [docs/features/ui_rules.md](docs/features/ui_rules.md)。
- **Loading(binding):** 所有 spinner 用 `AppLoadingIndicator`,`lib/` 下禁止原生 `CircularProgressIndicator`;分档规格见 [docs/features/ui_rules.md](docs/features/ui_rules.md)。
- **模态框(binding):** 业务代码只经 `showAppModal*` 打开模态,不直接调 `showShadDialog`;见 [docs/features/app_modal.md](docs/features/app_modal.md)。

## Go Bridge Organization

- 包内按职责拆文件(如 `dispatch_config.go`、`config_store.go`、`config_paths.go`);桥接导出按特性分组,不做单个大文件。
- 共享解析/归一化/传输 helper 放独立 helper 文件;Flutter FFI 优先窄 C ABI + JSON 负载,避免在 Dart 重复后端结构体。

## Adding a New Storage Backend

用户要求新增存储类型(FTP、SFTP、任何新远端 provider)时,按 [docs/AddingStorageBackends.md](docs/AddingStorageBackends.md) 的五层改动指南(Go config → Go backend → bridge → Dart model → Dart UI)执行。

## Build, Run And Validation

完整规则见 [docs/DEVELOPMENT_GUIDE.md](docs/DEVELOPMENT_GUIDE.md)。要点:

- 构建产物不进仓库根;本地构建输出走 `bin/`、`build/`,临时 `go build -o bin/...` 用完即删。
- macOS 启动用 `make run`(先建 `bin/bridge/libremote_storage_bridge.dylib` 再 Flutter);Windows 用 `scripts/run_windows.ps1`;Android 用 `scripts/build_android.ps1`。验证集成启动时优先这些脚本而不是裸 `flutter run`。
- 每个重构批次先跑最窄的有效验证;收尾前跑 `go test ./...` 和 `flutter analyze`(除非用户另定范围)。不用截图当冒烟证据;默认不跑本地冒烟,应用级验证交用户。
- 文档类改动跑 `make check-docs` + `git diff --check`。
- 任务诊断端点(`CV_DEBUG_ADDR`,`/debug/tasks`、`/debug/transfers`、`/debug/task-events` WS):见 [docs/features/remote_tasks.md](docs/features/remote_tasks.md#调试端点binding)。仅 loopback,禁绑 0.0.0.0。

## Git Workflow

- 完成实现并验证成功后创建常规非 amended 提交(用户明确说不提交除外);不提交编译产物。
- 新增功能同一变更集内更新 `README.md`;与 upcoming release 相关的改动维护 `CHANGELOG.md` 的 `## Unreleased`。
- **决策记录(binding):** 非平凡变更(行为/架构/契约/流程/测试策略/格式)在同一变更集中新增或更新一条 Agent Note([docs/notes/](docs/notes/README.md)),记录为什么与放弃了什么;机械改动豁免。

## Mandatory Review Before Commit

- 每个代码改动落地 `main` 前必须通过 P0/P1 级子代理评审;P0/P1 是 blocking,P2/P3 可延后但发现与解决方式必须记录在对应 `docs/features/*.md` 的 Known P2/P3 小节(完整叙事按性质分流:设计决策写成 [Agent Note](docs/notes/README.md),过程叙事进 [docs/PROJECT_GUIDE.md](docs/PROJECT_GUIDE.md);规则见 [docs/DOC_STANDARDS.md](docs/DOC_STANDARDS.md))。
- 评审子代理只给 `git show`/`git diff` 加简短 brief(提交哈希、动机、要考察的风险轴);评审发现改变范围时,先并入对应 feature 文档再落解决提交。流程细节见 [docs/DEVELOPMENT_GUIDE.md](docs/DEVELOPMENT_GUIDE.md)。

## Binding Design Principles(三大不变式简述,全文见 feature 文档)

1. **单一事实来源:** 挂载与页面共享同一个 bbolt 支撑的 `metadata.Service` inode 视图;`Manager.Acquire` 是唯一合法句柄入口;挂载写路径必须走 `Service.WritePath`/`EnsureDirectoryPath`/`DeletePath`;`TransferQueue` 绝不是显示来源。全文:[docs/features/mount_metadata_core.md](docs/features/mount_metadata_core.md#架构不变式binding)。
2. **Metadata 持久化契约:** journal 是唯一持久 mutation 来源;chunk 先 fsync+原子重命名再进 bbolt,退役递减 `nlink`;保护 manifest 是缓存清理唯一权威;worker 轮次串行、重试期限/依赖/静默屏障不可弱化;已触达 provider 的副作用不得对旧指纹重放;reset guard 保护 pending 数据;schema 不匹配即重建。全文:同上。
3. **任务列表首页可见性:** 桌面桥接与 Web API 必须未决任务先于终态历史(组内最新在前、ID 决胜),偏移分页在排序后;`pollActive` 用 `includeHistory: false`;排序 key 解析时间戳而非比较字符串;任何排序/分页改动配 `bridge/remote_task_ordering_test.go` 回归。全文:[docs/features/remote_tasks.md](docs/features/remote_tasks.md#架构不变式-3任务列表首页可见性binding)。

## Code Map 与探索落盘(binding)

- 任何代码库探索(含 Explore 子代理)——即使没有代码改动——在回合结束前把可复用结论写进对应 `docs/features/*.md`(正典)或 [docs/PROJECT_GUIDE.md](docs/PROJECT_GUIDE.md)(历史记录);目标是下个会话不重读同样的文件。
- 每次新增特性或特性文件集变化,同一变更集内更新对应 feature 文档与 [docs/CODE_MAP.md](docs/CODE_MAP.md) 索引。
