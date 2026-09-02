# Project Guide — 探索记录与历史评审存档

本文件是带日期的**历史存档**:评审结论与修复过程叙事、事故复盘、迁移记录。按时间倒序追加自包含条目;不设预算上限,但正典规则不在这里重复——现行契约在 `features/*.md`,发现以一行指针留在对应特性文档。开始新调查前先查这里是否已有结论(必读顺序见 [AGENT_GUIDE.md](AGENT_GUIDE.md))。

---

## 2026-09-02 Android 文件页 + 操作抽屉(app_shell / app_modal 域)

文件页的回收站、新建目录和上传原先占用搜索框下方的横向操作行；在手机首屏上既压缩内容区域，也会让长标签落入横向滚动。呈现层保留同一批 workspace 回调，但只在桶、目录或桶回收站存在可用操作时显示右上 48dp `+`，点击经 `showAppModal` 打开全宽动作抽屉。普通桶/目录列出回收站、新建目录、上传；桶回收站列出返回文件和可用时的清空操作。`test/widget_test.dart` 锁定无内联操作行、`+` 的语义和 48dp 命中区、抽屉项目及系统 Back 关闭，原有创建、上传、回收站导航和异步刷新回归改从该入口进入。P0/P1 评审未发现阻断项；建议的 P2 已同批补成非空桶回收站经 `+` 打开「清空回收站」并进入原确认框的回归，未遗留 P2/P3。

## 2026-09-02 Android 返回 tooltip 残留防回归(mobile_ui / app_shell 域)

用户第二次观察到文件管理二级页的「返回」提示及淡色 hover 背景在触摸后残留。审计确认顶栏返回仍通过 `AppTooltip` 创建 `ShadTooltip`；Shad 会把 Android tap 解释为 hover toggle，而系统 Back 或 route 切换不会向原按钮补发 leave。修复把平台分支收敛到 `app_tooltip.dart`：Android 只包 `Semantics(label: message, child: child)`，桌面/Web 继续创建可见提示；因而其它未来使用 `AppTooltip` 的 Android 图标也不会重现该状态。P0/P1 复审未发现阻断项；复审建议的 P2（实际二级页也直接断言「返回」语义）已同批补上，未遗留 P2/P3。现行强制规则与测试清单见 [mobile_ui](features/mobile_ui.md)，文件管理呈现归属见 [app_shell](features/app_shell.md)。

## 2026-09-02 Android 桶内对象紧凑列表评审(app_shell / file_actions 域)

Android 对象浏览已采用与桶列表一致的紧凑行和底部动作抽屉，桌面表格、网格及右键菜单保持原路径。提交前首轮 P0/P1 评审发现并同批修复：触底分页在紧凑行追加后未保持尾部可见、选择控件命中区小于 48dp、WebDAV 当前目录不可写时仍会显示/执行写操作，以及不支持递归目录下载时目录多选仍暴露无效下载入口。最终复审又在 280×480、1.5 倍字体、12 个追加项场景确认，不能以新内容高度差判断是否锚定；分页改为记录请求开始时的 `maxScrollExtent`，仅当用户之后已到达该旧尾部才跳到新尾部。移动端也不再渲染无本地镜像语义的“已同步”徽标，紧凑名称提升到 14sp。

最终 P0/P1 复审通过，无遗留 P2/P3。回归覆盖紧凑行、48dp 行尾/选择、长按与系统 Back、只读目录、文件/目录混合下载、窄屏大字号抽屉以及大字号分页；`flutter test`、`flutter analyze`、`go test ./...`、`make check-docs` 与 `git diff --check` 均作为收尾验证。

## 2026-09-01 Android 文件管理呈现复核(app_shell 域)

- Android 不再共享桌面文件 chrome：`mobile_file_manager_presentation.dart` 只持有布局，`FileManagerWorkspace` 继续是数据、异步请求、mutation 与位置 Back 栈的唯一事实来源。桶行的 `…` 用 `showAppModal` 底部抽屉展示可用动作，不能恢复挂载入口或行内设置图标。
- Flutter/Android 未发现主动 fullscreen 调用；状态栏信息不可见是 edge-to-edge 透明系统栏上的浅色图标。`AnnotatedRegion<SystemUiOverlayStyle>` 若包在 `ShadApp` 外，会被导航器 route 的 overlay 命中结果覆盖；必须位于 Android 首页 route 内并保留深色图标，模态可用已有嵌套 region 覆盖。

## 2026-09-01 Android 文件管理回归桌面 UX(app_shell 域)

截图审计确认独立 Android 页面已让标题、搜索、列表、操作入口和视图模式偏离桌面文件管理器。该轮曾把移动页改为无状态入口并复用桌面呈现，但后续移动端 UX 复核已推翻“桌面 chrome 唯一正典”：当前只复用 `FileManagerWorkspace` 运行时，Android chrome 改由独立呈现层维护。现行文件集与约束见 [app_shell](features/app_shell.md)，设计取舍见 [Agent Note](notes/implemented/architecture/2026-08-31-mobile-file-manager-presentation.md)。

---

## 2026-08-31 Android 文件页返回与桶图标回归(app_shell 域)

用户反馈移动桶行未沿用旧图标，且在二级文件页、桶或桶回收站的加载/错误期没有可用的左上返回；这时 Android 系统 Back 落入 `TabNavHistory`，会跳到另一个一级页。审计确认 Android 旧图标是 LocalCloudPan `sidebar/bucket.svg`，而新移动列表误换成 WhiteSur 存储桶图标；普通对象行也沿用 `LocalCloudPanFileIcon`。

共享 workspace 现以移动逻辑位置栈记录桶列表、桶+prefix 和桶回收站。目标位置在请求前提交，Back 先回到栈中前一位置；首屏、分页和操作收尾刷新都以位置+递增 epoch 校验，使用户离开后迟到的响应无法重新覆盖页面。子目录打开桶回收站后会恢复原子目录，目录 overflow 的「打开文件夹」也改为真正进入目录。同步目录的 latest-wins ticket 同时保护桌面和移动端的加载提交与缓存写入。桌面审计还发现只限制同步目标不足以阻止旧的桶、对象、回收站与分页请求覆盖当前视图，因此这些路径以统一 listing generation 门控 state、缓存和 finally 标记；取消同步目标时恢复原来的 loading/error 快照，并以快照中的真实桶列表、目录或回收站 target 续载，不能从旧可见状态猜测。补充审计还修复了静默刷新失败后 page-2 guard 残留，以及 Android A 被缺失的 B 替换时无执行者 loading 残留。正典见 [app_shell](features/app_shell.md)，取舍已并入 [Agent Note](notes/implemented/architecture/2026-08-31-mobile-file-manager-presentation.md)。针对性 widget 回归覆盖底栏历史优先级、左上返回及其加载中直点、加载中 Back、对象/回收站分页、回收站恢复、目录 mutation 的迟到响应、删除期间打开回收站、回收站来源目录，以及桌面/Android 同步 A/B 乱序和桌面取消同步的已加载、目标不存在、初始加载场景。

收尾评审补充确认 mutation 的失败也可能发生在 provider 已产生副作用之后。对象页缓存因此有独立 invalidation epoch，旧 page-2 在失效后不得回填；可见 mutation 刷新按逻辑源位置（Android 位置栈、桌面 resume target）而非旧 state 字段确认，桌面同步 discovery 期再加 listing generation fence，因而既不会在 B 的首屏尚未返回时取消 B，也能在 A→B→A 后刷新新的 A。Android 重命名失败 + 在途 page-2 与桌面 A→B 加载期间的 mutation 回归锁定这两个边界。

## 2026-08-31 Android 文件首屏与独立呈现层(app_shell 域)

用户要求取消 Android 首页，把文件管理做成独立维护的移动页面，并按大搜索、宽触控行、行尾操作和 FAB 的参考布局组织操作。探索确认旧实现虽已有移动组件，却通过 `file_manager_page.dart` 的私有 State extension 渲染，仍会让移动修改耦合到桌面页面。

现已收敛为 `FileManagerPage` 的桌面表面、`MobileFileManagerPage` 的 Android 专属表面，以及共享的 `FileManagerWorkspace` 数据/命令 controller。系统 Back 由移动文件页先处理目录与桶回收站，再落入 `TabNavHistory` 和退出；回调解绑改成 `clear()`，避免 method tear-off 比较。正典见 [app_shell](features/app_shell.md)，取舍见 [Agent Note](notes/implemented/architecture/2026-08-31-mobile-file-manager-presentation.md)。提交前审查没有 P0/P1；保留的 P2 是 workspace 仍作为 `file_manager_page.dart` 的 part，待 controller 明显扩张时再提升为独立 library。

## 2026-08-30 Android 配置备份还原 bbolt 崩溃(settings 域)

用户在 Android 首启「从备份存储还原」后观察到 Go `panic: page 2 already freed` 与 SIGABRT。事故后的 `bbolt check` 对落盘 `config.db` 通过，说明这不是备份内容或 `RestoreConfigBackup` 的 `DeleteBucket + CreateBucket` 事务把文件永久写坏；`page 2` 正是该文件的 freelist 页，错误发生在并发句柄各自维护的内存空闲页状态。

Flutter 将桥接调用放进 `Isolate.run`，因此轮询读取与还原可同时进入 Go。Android bbolt 使用 `fcntl(F_SETLK)`，锁属于进程而非单个文件描述符，多个同进程 `bolt.Open` 不能互相隔离，且关闭任一描述符会影响该进程锁。配置层已收敛为一个带 lease 的进程级句柄；根目录切换等待 lease 清空、关闭旧句柄后再更新路径，同一路径重复设置不扰动正在执行的调用。现行契约见 [settings](features/settings.md)，取舍见 [Agent Note](notes/implemented/bug-fix/2026-08-30-android-config-db-singleton.md)。

## 2026-08-30 Android 底部抽屉拟态框调整(app_modal 域)

全屏 surface 虽解决了早期上下裁切，却让「还原备份」等短确认框占满手机屏幕、在动作下方留下大块空白。现改为 `AppShadDialog` 统一的全宽底部抽屉：短内容按高度收缩，背景物理贴底且延伸到导航栏下，内容由内层 `SafeArea` 避让；长编辑器只填状态栏下、IME 后可用高度的 90%，顶部始终露出 scrim。

- 不能只把 `alignment` 改成 bottom：`SafeArea` 会把全局状态栏 inset 错加到短 sheet 顶部。外层保留状态栏的 dimmed band，再以 `MediaQuery.removePadding(removeTop: true)` 让 Shad 只保留侧边/底部安全区。
- Shad 0.54 的 `Align → Padding(viewInsets) → ConstrainedBox` 已天然使 sheet 在 IME 后贴键盘上沿；通过有限 `maxHeight`/fill-height 约束复用它，而不通过 `MediaQuery` 固定屏幕高度。同步编辑器、目录选择器和预览都显式标注 fill-height，紧凑态仍移除 `Expanded` 并整体滚动。
- Shad 小屏默认会去除圆角，故 Android 强制保留 20px 顶角；进入/退出使用 280ms `easeOutCubic` 上移与 220ms `easeInCubic` 下移。状态栏覆盖的是 scrim，图标固定浅色；导航栏覆盖 sheet，图标随主题切换。

现行契约与回归清单见 [app_modal](features/app_modal.md)，取舍见 [Agent Note](notes/implemented/architecture/2026-07-11-in-app-modals-over-os-subwindows.md)。

## 2026-08-30 Android 全屏拟态框评审(app_modal 域)

Android 业务拟态框统一迁入 `AppShadDialog` 全屏 surface 后,提交前 P0/P1 子代理评审发现两类 P1 边界:

- 同步编辑器与远端目录选择器只让中段列表伸缩;横屏 + IME 将 surface 压缩后,步骤栏/面包屑、输入行与动作的固定高度仍可触发 `RenderFlex overflow`。初版只滚动业务 `child`,复审又证明 Shad 标题/说明/gap/padding/SafeArea 仍可耗尽视口;最终紧凑态移除 `Expanded`,让 Shad 外层滚动包含全部 chrome 与动作,并缩小纵向 padding。同步输入共享 `FocusNode`,避免切换布局时丢焦收键盘。
- 桶设置/可见性、建目录、对象操作、高级设置、挂载、重置设置与关闭应用仍有固定 `Row` footer,窄屏大字体下可横向裁切;改为占满整行且右对齐的 `Wrap`,并以 240px / 1.5x 真实对象对话框回归。
- 账号编辑器字段本身有 14px 纵向间距,新截图的裁切实际发生在横向:Shad 焦点环向输入框外绘制 4px,但字段横向贴住无 padding 的 `SingleChildScrollView` 后被 `Clip.hardEdge` 裁掉左右边。Android `AppShadDialog` 改为默认传入 6px 内层 `scrollPadding`,不改字段高度、外层 padding 或裁剪策略。

组合回归覆盖 800×360 横屏、IME 压缩、1.5x 字体、聚焦保留与动作滚动可达;现行契约见 [app_modal](features/app_modal.md)。

## 2026-08-30 目录选择器调用方审计(settings / file_sync_p2p / account_management 域)

首启配置备份选择器的单根存储展示调查同时确认两个既有边界，均不由本次首启 helper 触发：

- 设置页切换备份 profile 或独立连接时，`ConfigBackupTarget.copyWith` 会保留上一条连接的 `bucket/prefix`；新来源若有同名桶，`isReady` 仍可成立并把备份写到旧路径。后续复用单根自动进入前，应先按来源 identity 变化使旧位置失效。
- 同步编辑器在已保存目标无法精确匹配时回退 `widget.buckets.first.config`；桶列表仍在异步加载、加载失败或过滤为空时会抛 `Bad state: No element`，非空时也可能借用无关首桶配置。后续修复应让空桶列表可安全构建，并显式呈现「已保存远端目标不可解析」，不回退无关账号。

同批提交前结构评审发现 `lib/pages/config_setup_page.dart` 基线已有 577 行，超过手写 `lib` 文件 500 行上限(P1)。首启账号草稿校验与保存原样移入 `lib/pages/config_setup_save.dart` part，宿主降至 451 行；该拆分不改变配置字段、校验文案或保存时序。
复审的 P2 指出新 part 尚未进入远端轮询、FTP/SFTP 正典与新增后端指南;同批补齐三处文件职责，并把指南的已实现 provider 列表与单根后端清单更新为 S3/WebDAV/百度网盘/FTP/SFTP 现状。

扩大验证时 `test/widget_test.dart` 的三个主布局用例会触发 Flutter 3.47 新的 `ListTile` 被有背景 `DecoratedBox` 包裹断言；在 detached `HEAD=9daea5a0` 上单独复现 `App shows main layout when config exists` 仍同样失败，确认与本批 picker/首启保存拆分无关。本批针对性 17 项用例与静态分析均通过；该基线测试兼容问题待独立修复。

## 2026-08-29 macOS Android 调测链落地与评审(android_dev 域)

新增 macOS Android 工具链(`make android-setup` / `make android-run`,设计决策见 [Agent Note](notes/implemented/process/2026-08-29-macos-android-dev-scripts.md);现状正典在 [android_dev](features/android_dev.md))。实机验证过程中钉住的关键上游事实:repository2-1 的 macOS emulator 归档只有 x86_64,该构建在 Apple Silicon 上跑不了任何镜像架构(arm64 镜像被 launcher 架构检查 FATAL、x86_64 镜像 HVF `Unknown error 0x4`),正解是 repository2-3 的同版本 `emulator-darwin_aarch64` 归档(不带 `package.xml`,需回填 sdkmanager 那份);Flutter 3.47 的 flutter-gradle-plugin 会自动 apply Kotlin 而 3.41 不会,`android/app/build.gradle.kts` 因此显式 apply。

提交前 P0/P1 子代理评审:

- **P0(同批修复)** — Flutter manifest 解析 `curl | python3 - <<PY` 的 heredoc 覆盖管道 stdin,全新机器(无 PATH Flutter)引导必死;改为先落盘 manifest 再传 argv,并单独实测解析出 stable 3.47.2 arm64 归档 URL。
- **P1(同批修复)** — `yes | sdkmanager --licenses` 在 `set -o pipefail` 下 sdkmanager 成功退出 0 时 `yes` 收 SIGPIPE(141),成功分支是死代码,此前仅靠 cmdline-tools 23 的弃用文案 grep 侥幸通过;改为 200 行有限答案文件重定向(与 ps1 同型)。
- **P2(同批修复)** — run_android.sh boot 等待循环对单次 adb 非零零容忍,一次抖动即杀脚本并遗留运行中的模拟器;探测加 `|| true`。
- **P3(同批修复)** — Makefile android-setup 缺 Windows gating;aarch64 emulator 替换每次重跑重复下载 400MB(加 `qemu/darwin-aarch64` + `package.xml` 存在性跳过标记);替换顺序改为先解压后删旧树。仍开放 P3 与修复指针见 android_dev「Known P2/P3」。
- 通过轴:bash 3.2 兼容、安装可重入、repository2-3 正则稳健性、模拟器信号设计(`trap '' INT QUIT TERM` + exec)、Kotlin 显式 apply 幂等(3.47 auto-apply 有 hasPlugin 守卫)、build_android_bridge 与 ps1 逐项对齐、文档一致性。

---

## 2026-08-29 AGENTS.md 文档体系拆分(迁移记录)

根 `AGENTS.md` 增长到 1630 行 / 327KB,超出会话注入上限——约第 430 行(Android Development Environment 条目中段)之后的内容对每个新会话不可见,Code Map 后半部(WinFsp、文件同步、设置、自动更新、FTP/SFTP 等 20+ 条目)实际已失效。本次拆分:

- 规则区(结构上限、hover/loading binding、构建/验证/提交/评审)拆入根 `AGENTS.md`(常备命令版)+ [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md)+ [features/ui_rules.md](features/ui_rules.md)。
- Code Map 34 个条目按域合并为 [features/](features/) 下 16 个正典文档;[CODE_MAP.md](CODE_MAP.md) 保留索引;带日期的评审叙事迁入本文件(见下)。
- 新增 [DOC_STANDARDS.md](DOC_STANDARDS.md)(分层规范 + 字数预算)与 `make check-docs` 门禁。
- 提交前经 P0/P1 子代理评审:无 P0/P1,APPROVE。P2(M2/M7 开放发现补回 mount_metadata_core 的 Known P2 指针)与 P3(账号 glyph/桶列表响应式列/自动更新超时数值/windows_dev Git-Go 前提/xpan 版本失准/DOC_STANDARDS 预算表缺 README 行与日期证据例外)已在同一提交修复;完整清单见评审记录(2026-08-29,agent 会话)。
- 同日第二批:引入 [notes/](notes/README.md) Agent Note 决策记录体系(借鉴 `../coding`,中文单语、去双语 sidecar 与 hash 门禁),`check_agent_notes.sh` 格式门禁并入 `make check-docs`;种子笔记 5 条(文档分层、journal-first 元数据核心、任务首页可见性、应用内模态、被拒的 Cloud Files 盘符选择),本文件 2026-07-11 模态条目改为指向对应 note。

对照表(旧 Code Map 条目 → 新文件):Mount Operation Queues → mount_metadata_core + remote_tasks + mount_queues_legacy + macos_webdav_mount(部分);Account Disable / Account Management / First-run Config Setup / Multi-Account Bucket Loading → account_management;File Sync / LAN P2P → file_sync_p2p;File Actions / Paste-Drag / File Preview / Object Delete-Trash → file_actions;Window Close-Tray / macOS Window Lifecycle / Navigation / Icons / Responsive Header → app_shell;Settings Layout / Diagnostic Logging / Auto Update / Global+Per-Account Proxy / Config Backup → settings;App Modal / Modal Sub-Window Shell → app_modal;Windows Crash Watchdog / Custom Chrome / Mount Presentation / Cloud Files Deletion / WinFsp → windows_platform;Windows Local Dev Workflow → windows_dev;Android Dev → android_dev;JWanFS SDK / FTP-SFTP → storage_backends。

---

## 2026-08-29 PR #5 合并评审(Android 任务队列集成,Transfer Queue 域)

- P3 — `remote_task_store_polling.dart` 的 Android 历史自动重载在 TransfersPage `IndexedStack` 子项未激活时也会从 store 全局轮询循环触发 `loadInitialHistory()`(仅带宽损耗;串行化读 gate 与严格递增的 `historyGrew` guard 保证正确性)。延后处理。
- P3 — 合并 diff 中 `config_setup_page.dart` 与 `transfers_page.dart` 是 main 的 `AppLoadingIndicator`/import 合并对 PR 旧副本的琐碎重放;无行为变化。
- 合并同时确认:Android 在任务队列重设计后也渲染列表内 `_RemoteHistoryPager`,自动重载只刷新首页;桌面保持仅 cursor 失效语义(现行契约已并入 [remote_tasks](features/remote_tasks.md))。

## 2026-08-28 任务明细面板评审(remote_tasks 域)

- P1(当日修复)— `_detailLine` 必须保持无界换行:它是长 provider 错误/依赖原因的唯一全文表面;行副标题刻意单行 + 省略号。现行契约已并入 remote_tasks「任务行视觉」。
- P3 — `remoteTaskContentIndent = 80` 重复前导 chrome 算术(12+18+10+28+12),由 helper 文档注释守护;评审跟进后两个消费方都 import 同一共享常量。
- P3 — 标签文字单行省略保护;`remoteTaskEventKindLabel('unknown')` → 未知操作;`test/remote_task_details_test.dart` 钉住标签列布局/每行传输 ID/无界换行契约。
- P3(2026-08-29 复审)— `RemoteTaskDetails` 的 原始操作 rawEventCount 回退分支无测试;`（已合并）` 后缀条件依赖 `event.folded`。
- 遗留 — `Colors.amber.shade700` 依赖浅色盘,深色模式时重审;`_RemoteInitialLoading` 只在历史 tab/全部筛选显示,其它筛选下首启先渲染「暂无任务」(既有早退,延后);`RemoteTask.name` 与 `remoteTaskEntryName` 两个近似派生待合并;rename 任务明细只显示新路径待扩展。

## 2026-08-22 → 2026-08-24 任务列表可见性评审(连续修复批次,remote_tasks 域)

七个 P1 连续修复(现行行为已全部并入 [remote_tasks](features/remote_tasks.md) 的「排序与可见性实现细节」;此处仅留过程脉络):

1. `pollActive` 与 `refresh()` 共享 `_polling`/generation/API 身份 guard,每次轮询更新 `_total`/`_queue`/`_freshness`/`_capabilities`;真实全零队列经 `queue.reported`/`page.hasTotal` 存在标志应用(而非 `total > 0` 真值)。
2. active-only 轮询返回全范围 `total`/队列计数(含历史)而只过滤响应行;修复观察到的 `共 0 项 · 已加载 200`/`历史 0`。桌面与 Web 用实际活跃行长度作无界页上限;此前 `limit=0` 修复无效,因共享 slicer 把零解释为 100 行默认。
3. `Manager.ListTaskGroups` 的 250ms memo 对命名空间拓扑(打开/释放/移除)也失效并带版本号;关闭 `warmKnownTaskNamespaces` 重开保留历史后短暂服务空快照的缓存竞争。
4. 队列分类器桌面/Web 对齐:运行时 `pending`→Waiting、`completed`/`cancelled`→History;failed/conflict 是未决(不可清理历史)。
5. 保留历史可从首个 active-only 页经 `canLoadMoreHistory` 加载(含 history-only 空 tab);动态任务变更 fan-in 在 warmed namespace 关闭时释放每 service 订阅,防止轮询周期保留已关闭 service/goroutine。
6. `NotifyTaskChanged` 覆盖补全(worker claim、`recoverDurableStates`、对账终态、用户 Cancel/Retry/Trigger、journal admission、两个 clear-history 路径),并经 `Service.groupCacheInvalidate` 丢弃组缓存。
7. `Manager.SubscribeTaskChanges` 以与 `Acquire` 相同的 `m.mu → taskChangeMu` 顺序安装动态 hook 并订阅既有 service,关闭迟到命名空间注册竞争;service 退订关闭通道使 fan-in goroutine 退出。

附带 P2(已修复):`TaskEventsHandle.dispose` 关闭活动 WebSocket,`bridge/debug_tasks.go` 检测 peer close 服务端退订;`remote_task_store` 拆分 parts 与 wire 模型迁移满足 500 行上限;两种 `ClearTaskHistory` 报告不同任务组并通知订阅者。

## 2026-08-17 M2–M7 系列评审遗留(mount_metadata_core 域)

- M2/M7 评审 P2(部分仍开放):每页 Acquire/Release 翻动 worker/db 生命周期;metadata `ListPage` 只返回直接子项(旧 S3 flat-prefix listing 含深层 key);指向前缀是文件时报错而非列出。页面句柄生命周期后续移到会话域。
- M6c 评审 P2/P3:页面任务 ID ↔ worker 传输快照 ID 未映射;挂载字节读不能服务未确认页面上传 chunk;Web 上传端点仍 provider-direct;`.`/`..` 页面段校验待做;WebDAV「MOVE applied then retry」HTTP 端到端 fixture 是测试缺口。现行表述见 mount_metadata_core 各 Known P2/P3。

## 2026-08-14 Windows Cloud Files 跨客户端诊断批次(windows_platform 域)

Explorer 上传后目录重命名、重启安全移动、有界空闲刷新三个任务的实现与回归锚点(现行契约见 [windows_platform](features/windows_platform.md)「Explorer 上传后目录重命名」「重启安全的远端移动」「有界空闲目录刷新」)。同批次确认:watcher 回调只 stage 本地状态,CFAPI 回调保持非阻塞。

## 2026-08-10 Cloud Files 发布日志排查(windows_platform 域)

Release 构建无 `app.log.level` key 时桥接保持 `Silent`,`bridge.log` 可能为零字节;请求写回日志前必须确认设置里级别已切「调试」、会话晚于该改动、日志时间戳/大小在推进(现行提示在 [settings](features/settings.md) 诊断日志节)。同日验证 metadata 缓存禁用与 P0 轮询独立性。

## 2026-07-30 macOS WebDAV 审计批次(macos_webdav_mount 域)

- Finder `PROPPATCH` 误路由(exact `O_RDWR` 走可写分支)修复——该 bug 在 provider 边界之上,修复前影响全部 macOS 挂载上游(S3/WebDAV/Baidu/FTP/SFTP)。
- 提供商影响矩阵:SFTP 禁用活跃目录 P0 轮询(每刷新新建 SSH/SFTP 会话,递归元数据爬取与用户目录打开在 WebDAV 层不可分);S3/FTP/WebDAV/Baidu 保留有界轮询;新 provider 出现同种放大时,先审计其连接/重试行为再加显式策略,不改本地优先写回语义。
- macOS 15 `webdavfs_agent` 延迟状态发布(配额 XML <1ms 可得而 `statfs` 阻塞 ~90 秒)的排查与回退清单;并发运行安装版与调试构建对同一 SFTP 账号的压力复现(90s → 0.45–0.75s)。现行 gotcha 见 macos_webdav_mount 配额投影节。

## 2026-07-11 模态呈现策略统一(app_modal 域)

同步/账号/远端目录编辑器默认路径从 OS 子窗口切换为应用内模态(`showAppModal` + `asDialog: true`);OS 子窗口保留为 `kDebugMode && USE_MODAL_SUB_WINDOWS` 的实验路径。决策与替代方案已正典化为 [决策记录](notes/implemented/architecture/2026-07-11-in-app-modals-over-os-subwindows.md);现状见 [app_modal](features/app_modal.md)。同日修复 `StorageProtocolCard` 与 `DesktopModalShell` 关闭按钮的 hover 回归(反面板经见 [ui_rules](features/ui_rules.md))。

## 2026-07-02 → 07-08 应用内更新修复批次(settings 域)

镜像只套下载 URL(API 403)、构建架构匹配(`get_build_info`)、无 Content-Length 不定态进度、超时/镜像探测/任务类型 `app_update`、安装器缓存续传、下载完整性(大小 + SHA-256 digest)、Windows 关闭句柄、HTTP/2 流重置的 Range 重试与被撤回的 HTTP/1.1 强制、macOS bundle 重启与镜像模式持久化。现行契约已并入 [settings](features/settings.md) 自动更新节。

## 2026-07-02 v1.2.0 发布工件回归(settings 域)

`v1.2.0` 的 GitHub release 含 Windows CLI 归档但无桌面 `yunjuan-windows-amd64.zip`/安装器:tag 上的 `build_desktop_packages.sh` 在续行的 PowerShell 命令(调 Inno Setup)里放了 shell 注释,提交 `616a3b0c` 在 tag 之后才修复该 CI 命令。**不要**把 v1.2.0 当桌面运行时回归的证据——该 tag 没有发布官方 Windows 桌面工件。官方 v1.1.9 与 v1.2.1 桌面 ZIP 静态比对:同为 639 文件布局、相同 Flutter 引擎/插件依赖集、x86-64 EXE/DLL/AOT 架构、相同导入运行时 DLL 名;只有 `data/app.so`、`remote_storage_bridge.dll` 与 updater 载荷大小变化——排除普遍缺 DLL/错架构包,但不排除部分原位更新失败或用户特定启动数据故障。

## 2026-07-01 macOS Cmd+V 粘贴通道(file_actions 域)

Flutter macOS 引擎 `performKeyEquivalent` → TSM 吞掉 `paste:` selector 的根因分析与 NSWindow 层截获方案(现行契约见 [file_actions](features/file_actions.md) 本地文件粘贴节)。

## 2026-06-27 文件同步删除检测探索(file_sync_p2p 域)

远端递归扫描深度、本地目录 key(`localDirSide`)、空远端目录 `OpEnsureLocalDir`、三视图对账与删除推断表、重命名配对——现行模型见 [file_sync_p2p](features/file_sync_p2p.md) 对账模型节。

---

> 追加新记录时:放在本注释上方、按日期倒序;标题带日期与所属特性域;正文自包含(引用文件路径 + 结论);正典化的行为同步写入对应 `features/*.md` 并在这里留一行指针。
