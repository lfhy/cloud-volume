# Project Guide — 探索记录与历史评审存档

本文件是带日期的**历史存档**:评审结论与修复过程叙事、事故复盘、迁移记录。按时间倒序追加自包含条目;不设预算上限,但正典规则不在这里重复——现行契约在 `features/*.md`,发现以一行指针留在对应特性文档。开始新调查前先查这里是否已有结论(必读顺序见 [AGENT_GUIDE.md](AGENT_GUIDE.md))。

---

## 2026-08-29 AGENTS.md 文档体系拆分(迁移记录)

根 `AGENTS.md` 增长到 1630 行 / 327KB,超出会话注入上限——约第 430 行(Android Development Environment 条目中段)之后的内容对每个新会话不可见,Code Map 后半部(WinFsp、文件同步、设置、自动更新、FTP/SFTP 等 20+ 条目)实际已失效。本次拆分:

- 规则区(结构上限、hover/loading binding、构建/验证/提交/评审)拆入根 `AGENTS.md`(常备命令版)+ [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md)+ [features/ui_rules.md](features/ui_rules.md)。
- Code Map 34 个条目按域合并为 [features/](features/) 下 16 个正典文档;[CODE_MAP.md](CODE_MAP.md) 保留索引;带日期的评审叙事迁入本文件(见下)。
- 新增 [DOC_STANDARDS.md](DOC_STANDARDS.md)(分层规范 + 字数预算)与 `make check-docs` 门禁。
- 提交前经 P0/P1 子代理评审:无 P0/P1,APPROVE。P2(M2/M7 开放发现补回 mount_metadata_core 的 Known P2 指针)与 P3(账号 glyph/桶列表响应式列/自动更新超时数值/windows_dev Git-Go 前提/xpan 版本失准/DOC_STANDARDS 预算表缺 README 行与日期证据例外)已在同一提交修复;完整清单见评审记录(2026-08-29,agent 会话)。

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

同步/账号/远端目录编辑器默认路径从 OS 子窗口切换为应用内模态(`showAppModal` + `asDialog: true`);OS 子窗口保留为 `kDebugMode && USE_MODAL_SUB_WINDOWS` 的实验路径。同日修复 `StorageProtocolCard` 与 `DesktopModalShell` 关闭按钮的 hover 回归(反面板经见 [ui_rules](features/ui_rules.md))。

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
