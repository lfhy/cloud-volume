# Remote Tasks — 统一任务投影、列表可见性与传输兼容层

统一 `RemoteTask` 投影是唯一远端操作 UI 来源:任务页、侧栏、同步卡、预览、批量对话框、更新进度全部读它。`TransferQueue` 只是执行/本地生产者兼容门面。

## 架构不变式 3:任务列表首页可见性(binding)

- 桌面桥接(`bridge/remote_task_ordering.go`)与 Web API(`go/webapi/remote_task_ordering.go`)必须把未决状态(`pending`、`waiting`、`blocked`、`retry_wait`、`running`、`verifying`、`cancel_requested`、`reconciling`、`failed`、`conflict`)排在终态历史前;组内最新在前;ID 决胜。偏移分页在该排序**之后**应用。这不是装饰:文件管理页在 metadata 任务 active→终态时刷新列表,首页被 done 历史淹没会静默破坏页面/挂载同源刷新(2026-08-21 曾观察到 558 个 done 组把新任务挤出 limit=100)。
- `RemoteTaskStore.pollActive` 使用 `includeHistory: false`,活跃任务永远在第一页。历史只由页面进入时的 `loadInitialHistory()` 流程(调 `loadMore` 到首个 **100** 行)或用户主动 `loadMore` 获取;这些请求都带 `includeHistory: true`。任何新的轮询调用方必须保持该分离。
- `refresh` 里的 `completeSnapshot` 对账只在请求确实代表全量任务集时允许(`includeHistory && cursor.isEmpty && nextCursor.isEmpty`);否则 loadMore 合并的历史行会被静默清除。
- 排序 key 必须解析时间戳(`time.Parse` RFC3339Nano / RFC3339)而不是比较 wire 字符串,运行时快照(本地时区 `createdAt`)与 metadata 任务(UTC RFC3339Nano `updatedAt`)才能正确交错。
- 文件管理页刷新与 `RemoteTask` 排序耦合:任务列表排序或分页的任何改动必须配回归测试证明活跃任务留在第一页(`bridge/remote_task_ordering_test.go`)。

## 排序与可见性实现细节

- `TransfersPage` 渲染队列标签行(`_RemoteQueueTab`,按 binding hover 规则的独立 StatefulWidget),既显示各队列计数又切换 `_remoteStatusFilter`;标签是主要队列导航,下拉是次级控制。
- 回归:`bridge/remote_task_ordering_test.go` 钉住 118 done + 2 active → 首页含两个活跃任务、最新活跃在前。
- `bridge/dispatch_remote_tasks.go` + `bridge/remote_task_visibility.go` 与 Web 等价物分离**计数范围**与**响应可见性**:`remoteTaskCountInput` / `webRemoteTaskCountInput` 计算 `total` 与 `queue` 时始终包含终态历史;`remoteTaskResponseItems` / `webRemoteTaskResponseItems` 只在 active-only 轮询中隐藏终态行。active-only 用实际活跃行长度作为页上限,因为 `*TaskPageSlice(..., 0)` 表示常规 100 行默认。`remote_task_visibility_test.go` 钉住 200 历史 + 101 waiting → 计数 301/200/101 且 101 个活跃行全部返回。
- `RemoteTaskStore.tasks` 仅在本地生产者活跃时可用;终态任务页历史必须来自 Go。`TransferQueue` 现在移除终态本地投影,只持久化活跃生产者交接;重启时丢弃旧 v2 payload,因为 Dart 生产者不能恢复。修复了 `backend tasks=0, transfers=0` 配 `历史 200` 列表的诊断特征。
- `Manager.ListTaskGroups` 缓存任务组 250ms,但 memo 有版本号,在每个持久任务转换**以及**命名空间 acquire/release/removal 时失效。缓存构建与任一类变化竞争时重试而不是发布瞬时空/非空投影;否则桥接会在页面句柄开合之间交替真实历史与 `total=0`。`TestTaskGroupCacheTracksNamespaceAcquireAndRelease` 钉住该拓扑不变式。
- `RemoteTaskPage` 显式报告 `total=0` 时,`RemoteTaskStore` 即使在 active-only 轮询中也驱逐全部缓存 Go 行;这是唯一权威描述整个投影为空的 active-only 响应。终态 Dart 生产者快照仅保留在 `executionTask`,批量对话框可渲染终态而不重新出现在任务列表。`remote_task_store_test.dart` 与 `batch_task_progress_dialog_test.dart` 钉住两条路径。
- `RemoteTaskStore.canLoadMoreHistory` 即使 active-only 轮询没有历史 cursor 也暴露首个历史请求。`TransfersPage` 必须在空态/过滤空态之前渲染历史分页器,否则 history-only 队列不可达。`_RemoteHistoryPager` 是**最后一个 `ListView` 子项**而非固定卡片 footer:渲染 `历史已显示 loaded / total` 与 `加载下一页(还剩 n 条)` 按钮(busy = 居中「正在加载历史…」spinner 行),因此只有用户滚到最后一行才进入视野;满首页刻意把它压在折叠线下。`showHistoryPager` 早退逻辑保证可达性——history-only 队列跳过空态,渲染卡片,其列表以分页行结束(`_RemoteInitialLoading` 在首页读取时)。WebSocket 只驱动新的 active-only 轮询(计数/活跃行),刻意不流式传输无界终态历史,显式分页器是后续历史的权威。`_applyQueue` 在权威 active-only 轮询报告更大历史总数时必须同时失效 `_nextCursor` 与 `_hasLoadedMore`:新终态行排到前面时偏移分页位移,仅重开耗尽标志会跳过第二次后续完成。缓存行只有 `done`/`canceled` 是可移除历史;`failed`/`conflict` 留在 active-only 响应与重试队列直到它们远端消失。桌面与 Web 队列分类器把运行时 `pending` 归一为 waiting、`completed`/`cancelled` 归一为历史,匹配 Dart wire 解析。
- `TransfersPage` 位于 `IndexedStack`:必须在 post-frame 回调调度 `loadInitialHistory()`,绝不从 `didUpdateWidget` 同步调用,因为其 task-store 通知会在父构建期间到达侧栏动画监听者。`SidebarTransferStatus._syncAnimation` 独立把 AnimationController 更新从 `SchedulerPhase.persistentCallbacks` 推迟,作为安全网。头部 `清理全部历史 <server count>` 动作在 `queue.history > 0` 时总是显示(包括选中激活或仅缓存首页时);它不带 ID 调 `clearHistory()`,而 `清理历史 <n>` 仍是选中行动作。`transfers_page_batch_actions_test.dart` 钉住两条路径与构建期动画回归。
- 全量历史清理由 `go/mount/metadata/tasks_compaction.go` 规划:一次反向 `Seq` 遍历累积后续未决操作引用的 inode/parent ID、检查 applied write 的 `ContentRef`,然后只通过公共 `deleteTaskHistoryOp` 索引清理删除安全终态行。刻意等价于 `canCompactTaskOp` 的逐行守卫(`tasks_history.go` 中选中行路径的精确守卫);`tasks_compaction_test.go` 钉住 later-parent 依赖与大终态批次。清理请求 pending 时,`_RemoteBatchAction` 只在匹配的清理按钮内渲染紧凑 spinner;`transfers_page_remote_filters.dart` 把抽取的筛选控件保持在每文件上限以下。
- 队列级「立即同步」:`lib/pages/transfers_page_remote_header.dart` → `RemoteTaskStore.triggerAllRemoteTasks` → 桌面 `trigger_all_remote_tasks` / Web `trigger_all_remote_tasks` → `Manager.TriggerPendingTasksFor` → `Service.TriggerPendingTasks`。一次后端调用处理范围内全部 **metadata** pending 组,只设置 `NextAttemptUnixNano=now` 与一次性 `SkipQuiet`,发一个任务变更 tick 并唤醒 worker。Web 调用需要非空活跃 ProfileID(`webTaskSyncProfileID`),绝不回退 Manager 的全命名空间空范围;拒绝/错误动作返回非 2xx,Dart 不报告假零任务成功。它刻意绕过重试期限,但**不得**直接执行 provider 工作或弱化 `Worker.claimDue` 的依赖检查:同 inode 排序、父/move 屏障、恢复/取消处理、一次一个 provider 执行仍是权威。`tasks_sync_test.go` 钉住父→子与 mkdir→rename 批量触发(前置未终态时后续 op 不被 claim);`remote_tasks_test.go` 钉住空 ProfileID 拒绝;`transfers_page_batch_actions_test.dart` 钉住一次前端调用及其范围 spinner。`_RemoteBatchAction` 还确保 clear/sync spinner 只出现在实际 in-flight 的动作上。
- `lib/state/remote_task_store_polling.dart` 为活跃轮询与历史刷新持有**一个**串行化 `_inFlightRead`。`loadMore` 必须先加入该 gate 再在其后重试,而不是把另一页的 `refresh()` 当作完成;不要恢复基于 timer 的 busy 等待或并行读取(暴露瞬态手动加载按钮、可能损坏 cursor)。`loadInitialHistory` 以常规大小走活跃前缀页,再把剩余终态行容量作为 `limit` 传入——≤100 终态行的队列完整渲染,更大的队列用一个有界首页;`isLoadingMoreHistory` 持有固定分页 spinner 等待其请求排在活跃轮询后。`_applyQueue` 在终态数增长时推进非破坏性 `_historyCursorVersion`;自身检测到增长的续接响应在合并前丢弃(其 offset 已位移),用户翻页请求在同一读 gate 后重试第一页**一次**。页面进入加载把该位移让给外层剩余行循环——有界首页响应绝不追加完整第二页;第二次位移让回可见分页器而不是永远自旋。`remote_task_store_cleanup.dart` 独自推进破坏性 `_historyEpoch`、等待更旧读取、清历史前 poll 新数据;过期 clear/history 响应绝不能重置新绑定或复活已删行。`remote_task_store_test.dart` 钉住 100/150 页推进、cursor 耗尽后两个 WebSocket 式历史增长事件、保持 100 行上限的首页增长、in-flight 续接增长、持续增长活性、串行化读取、首页失败后重试、cursor 失效、clear/history 竞争、API 重绑定;`transfers_page_batch_actions_test.dart` 钉住可见固定分页器与 `IndexedStack` 非活跃→活跃转换。
- 任务变更订阅与生命周期绑定:`Service.Close()` 关闭其监听者,`Manager.SubscribeTaskChanges()` 在通道关闭时移除每个 service 注册。这是必须的:列表轮询每周期打开并释放 history-only 命名空间;保留闭包会为 WebSocket 客户端生命周期泄漏已关闭 service 与 fan-in goroutine。浏览器构建选择 `remote_task_events_web.dart` 而不是导入 `dart:io`,保留轮询回退。
- `lib/models/remote_task_wire.dart` — wire 模型(`RemoteTaskPage`、`queue.reported`/`page.hasTotal` 存在标志等);store 按职责拆分为 `remote_task_store_polling.dart` / `remote_task_store_merge.dart` / `remote_task_store_cleanup.dart` / `remote_task_store_local.dart`,拆分同时满足 500 行上限。
- 历史清理是显式的:选中终态行把其 ID 经 `clear_remote_task_history` 发送,Go `ClearTaskHistoryIDsFor` 只删除那些终态 journal 条目(保留仍保护后续依赖的任何内容);未选中的「清理历史」动作删除范围内全部可压缩终态历史。Metadata 物理快照(`metadata-op-<namespace>-<seq>`)从不投影为本地行——它们已嵌入持久任务。

## 调试端点(binding)

`make run` 导出 `CV_DEBUG_ADDR`(默认 `127.0.0.1:8765`);桥接在首次桥接调用时惰性启动仅 loopback 的 HTTP 监听(`bridge/debug_tasks.go`):

- `GET /debug/tasks` — 每个命名空间的活跃任务投影:`id/state/status/lastError/retry/nextRetryAt/seq/createdAt/updatedAt`。任务疑似卡住(如 验证远端 不解决)先用它——`lastError` + `retry` 区分「探测持续失败重试中」与「worker 停了」。
- `GET /debug/transfers` — metadata 任务背后的运行时传输监控快照(`id/type/status/detail/bucket/key/bytes`)。
- `WS /debug/task-events` — 推送通道。metadata worker 在每次 op 状态转换(`worker_execute.go`)调 `Service.NotifyTaskChanged()`;`Manager.SubscribeTaskChanges()` 把既有与新获取命名空间动态扇进一个通道,socket 每个合并信号发一个 `{"event":"changed"}` tick。桌面 `RemoteTaskStore`(`lib/state/remote_task_events.dart`)绑定时经 `dart:io` WebSocket 连接,每个 tick 触发 `pollActive()`,2s 退避静默重连;`remote_task_events_web.dart` 刻意用轮询,因为调试监听仅 loopback。轮询(700ms 活跃 / 2s 空闲)仍是正确性回退,推送是优化,绝不是数据源。客户端 dispose 关闭 WebSocket;服务端读 peer close 并立即退订。`make run` 还把地址作为 `--dart-define=CV_DEBUG_ADDR=...` 传入。

**Notify 覆盖率(binding):** 每个持久 op 状态转换必须调 `NotifyTaskChanged()`——worker claim/execute、对账成功/失败/取消、用户 Cancel/Retry/Trigger、启动 `recoverDurableStates`、journal admission(`remoteMutation.finish`)、两个 clear-history 路径。新增修改 op 状态却不通知的调用点是 bug。`Service.groupCacheInvalidate`(由 Manager 安装)在每个 notify 时丢弃 250ms 组 memo,推送触发的轮询读到新数据。

`CV_DEBUG_ADDR=`(空)禁用监听。绑定 0.0.0.0 或暴露到 localhost 之外是禁止的;这是仅诊断面。

## 远端任务显示链路

- `go/s3/transfer_monitor_lifecycle.go` 派生 kind 感知的 running 阶段、在 queue→running 转换中保留 source/target 字段、保持排队取消终态、引用计数嵌套 provider 阶段使外层挂载任务不会提前完成;legacy 挂载与非 S3 生产者在投影前附加 `ProfileID`。
- `bridge/remote_task_runtime_wire.go` / `go/webapi/remote_task_runtime_wire.go` 保留本地目的地、source/target 路径、当前文件字节计数器与 multipart range 字段。Flutter `RemoteTaskDisplay` 渲染本地化阶段与 source→target 摘要。
- `bridge/dispatch_app_install.go` 在逻辑 key 中保留 asset 名并在安装器边界关闭取消;`lib/widgets/settings_update_task_policy.dart` 让 Flutter 取消按钮跟随该能力,运行时快照缺失时保守禁用。
- `go/s3/transfer_monitor_current_file.go` 提供 seed-only 恢复记账与结构化 part range,恢复字节不再膨胀吞吐。
- `go/s3/transfer_monitor.go` / `transfer_monitor_lifecycle.go` / `transfer_monitor_current_file.go` / `transfer_monitor_readers.go` / `go/sync/executor.go` / `go/storage/tracked_download.go` / `go/storage/tracked_mutation.go` — 物理快照携带拥有 profile 身份、kind 感知阶段、seed-only 恢复记账与结构化当前文件/part 进度。共享 mutation 包装器给 FTP、SFTP、WebDAV、百度网盘 copy/move/delete 调用与 S3 相同的快照生命周期,不替换已在运行的挂载队列。直接页面 rename 经 tracked move 路径发送任务 ID;持久挂载 rename 行保留原始源 + 最终目标。`lib/state/remote_task_store.dart` 把这些快照与 `transfer_queue_remote_tasks.dart` 提供的显式本地适配器合并,清除旧桥接版本的 `transfer:metadata-op-*` 行,并对账完整页面而不是保留缺失远端任务。Metadata 后端页面生产者可为瞬态上传/删除对话框发布不可取消的执行-only 快照;它们排除在 `tasks` 与 profile 聚合外。`transfer_queue.tasks.v1` 因早于生产者所有权元数据被刻意失效;只恢复 v2 行。所有可见任务行使用统一 store;旧 `TransferQueue` 仍是执行/本地兼容生产者,绝不是任务显示来源。
- `lib/models/remote_task.dart`、`remote_task_display.dart`、`lib/state/remote_task_store.dart`、`lib/pages/transfers_page*.dart`、`lib/widgets/remote_task_widgets.dart`、`lib/widgets/sidebar_transfer_status.dart`、`lib/pages/file_sync_tasks_page.dart` 渲染有效操作、依赖、可展开原始事件、物理阶段、取消/重试/触发、历史。挂载范围读把文件路径作为主标签、当前 `bytes=` 区间作为 `读取范围`;没有页面/侧栏/同步卡回退到 `TransferQueue`。

## 任务行视觉

`RemoteTaskRow`(`lib/widgets/remote_task_widgets.dart`)布局 [checkbox 18 + 间距 10 + `_KindIconChip` 28 + 间距 12 | 标题/副标题 | 右侧控件];标题列起始于 **80px**,共享常量 `remoteTaskContentIndent`(80,定义在 `remote_task_style_helpers.dart`)是展开的 `RemoteTaskDetails` 面板与行分隔线的 binding 缩进——改前导 chrome 时保持三者对齐。标题**只显示条目名**(`remoteTaskEntryName`:`operationPath` 最后一个非空段,kind 标签回退)——kind chip 承载操作类型,`RemoteTaskDetails` 以 操作/所属桶/完整路径 行开头,动词、桶、完整路径绝不回到行标题。展开面板在 `lib/widgets/remote_task_details.dart`(公开):每行固定 60px 标签列(`_detailLabelWidth`)+ 换行值,metadata、事件、传输 ID 对齐;journal 事件渲染在一个 事件记录 分组标签下(后续行空标签,同 传输 模式),值 `#<seq> remoteTaskEventKindLabel(path)(已合并)`;物理任务 ID 每行一个(首个带 传输 标签)而不是 `·` 连接块。活跃状态(running/verifying/cancel_requested/reconciling)在 `RemoteTaskStatusBadge` 胶囊旁显示一枚紧凑 12px spinner(浅底 + 发丝边框);动作按钮在徽标右侧。`RemoteTaskDetails` 用 3px 类型色强调条(`IntrinsicHeight` 行;统一边框规则禁止 radius 下的左-only BorderSide)置于 muted 面板上(依赖 amber、错误 destructive)。纯查表(`remoteTaskSpeedSummary`、`remoteTaskSubtitle`、`remoteTaskEntryName`、`remoteTaskStatusLabel/Color`、`remoteTaskKindIcon/Color/Label`)在 `lib/widgets/remote_task_style_helpers.dart`——直接 import 它(transfers_page.dart、sidebar_transfer_status.dart 这么做);`remote_task_widgets.dart` 不再定义它们,文件保持 500 行上限以下。`RemoteTaskStatusBadge` 公共 API 与 `batch_task_progress_dialog.dart` 共享。

值列(含旧 `_detailLine`)必须保持无界换行——它是长 provider 错误/依赖原因的唯一全文表面;行副标题刻意保持单行 + 省略号。`test/remote_task_details_test.dart` 钉住标签列布局、每行传输 ID、无界值换行契约。

加载:队列首次历史读取渲染 `_RemoteInitialLoading`(标准 22/2.4 主体 spinner + 「正在加载任务…」)于列表卡片内,条件 `store.tasks.isEmpty && store.isLoadingInitialHistory`;列表末尾分页行取代旧固定 footer;全部队列 spinner(批量按钮、分页 busy 行、行状态/动作)按 [ui_rules](ui_rules.md) 用 `AppLoadingIndicator`。`_RemoteInitialLoading` 只在历史 tab/全部筛选激活时显示——进行中/等待中/失败 筛选下首次激活先渲染「暂无任务」(既有早退,延后处理)。`transfers_page_remote.dart` 逼近 500 行上限——下次添加前拆出队列标签/筛选。

阶段显示:metadata 任务的 Go `Phase` 是子系统标记(`provider`/`verification`/`dependency`/`history`,设置于 `go/mount/metadata/tasks.go`),不是用户阶段——`RemoteTaskDisplay.phaseLabel` 把它们映射为 `''`,并抑制以 `cancel requested` 开头的 `phaseDetail`(取消/对账英文句子),终态行显示 已完成/已取消、取消行显示 正在取消/正在对账,由徽标/副标题承载;`BlockedReason == 'waiting for journal dependencies'` 经 `remoteTaskBlockedReasonLabel` 本地化为 等待前置操作完成(副标题 + 依赖明细行都用),侧栏活跃行回退是 `remoteTaskStatusLabel`(不是硬编码 进行中),真实物理阶段(uploading/quiet_period/mount_read/…)保留标签。`test/remote_task_display_test.dart` 钉住以上全部。

条目名标题:同视图同名行仅靠明细区分(后续考虑副标题带父目录);`RemoteTask.name` 与 `remoteTaskEntryName` 是两个近似派生、优先级不同——加第三个之前先合并;rename 任务明细只显示新路径(`sourceTargetSummary` 扩展到 rename 或在有摘要时去掉重复 完整路径);侧栏 hover 行与同步卡单行刻意保留完整路径(那里没有展开面板);`_KindIconChip` 把操作动词作为 `AppTooltip`。

**Known P2/P3:** 见 [PROJECT_GUIDE](../PROJECT_GUIDE.md) 2026-08-22/24 任务可见性评审、2026-08-28 任务明细评审、2026-08-29 PR #5 合并评审记录。

## Transfer Queue(通用传输队列兼容层)

`TransferQueue` 是手动上传/下载与 Dart-only 工作的执行/本地生产者兼容门面。它把生命周期变化镜像进 `RemoteTaskStore`;没有可见任务页、侧栏、同步卡、预览、批量对话框、更新状态把该队列当显示源。Go journal/运行时工作直接投影进同一 `RemoteTask` 模型。

- `lib/state/transfer_queue.dart` — 核心 `TransferQueue` 单例。轮询(非流式):`pollNow()` 调 `api.listTransferJobs()`,`refreshFromSnapshots` 把 `TransferSnapshot` 字段合并进 `TransferTask`(`bytesCompleted`/`totalBytes`/`itemsCompleted`/`totalItems`/`speedBytes`/…)。`_ensurePolling` 在 `hasRunning` 时用 `_activePollInterval` = 700ms,否则 `_idlePollInterval` = 2s。
- `lib/state/transfer_queue_lifecycle.dart` — API 绑定、任务创建、终态成功/失败/取消转换;成功完成归一化字节与 item 两个进度维度(Go `finishTransfer` 已在桥接返回前设置 BytesCompleted=TotalBytes 与 ItemsCompleted=TotalItems,Flutter `markTaskDone` 立即镜像该不变式——否则最后一次轮询计数如 `10 / 20` 会在状态变 done 后残留约 2 秒)。
- `lib/state/transfer_task.dart` — `TransferTask` 模型;`TransferKind { upload, download, copy, move, delete, appUpdate }`;`progress` = `bytesCompleted/totalBytes`,`totalBytes<=0` 时为 0。`transfer_queue_lifecycle.dart` 乐观创建 pending 本地任务,`refreshFromSnapshots` 用 Go 快照覆盖进度字段——活跃期间 Go 是权威。
- `lib/models/transfer_job.dart` — Go JSON 的 `TransferSnapshot.fromJson` 镜像。
- `go/s3/transfer_monitor.go` — `TransferSnapshot`(:15)JSON:`id,type,bucket,key,localPath,targetPath,status,statusDetail,createdAt,bytesCompleted,totalBytes,itemsCompleted,totalItems,currentFileKey,currentFileBytesCompleted,currentFileTotalBytes,speedBytes,error`。`startTransfer`(:54)置 running + TotalBytes(默认 StatusDetail "uploading");`advanceTransfer`(:246)累加字节 + 计算 `speedBytes`;另有 `AddTransferTotal`/`AddTransferItems`/`AdvanceTransferItems`、`finishTransfer`(:263;TotalBytes>0 时 completed=total)。经桥接 `list_transfer_jobs` 与 `go/webapi/invoke.go` 暴露。
- `lib/state/transfer_queue_*.dart` — 按关注点拆分:metrics、sync、本地进度、前台、存储、目录子项。
- `go/s3/transfer_history.go` — `ForgetTerminalTransfers` 在显式 RemoteTask 历史清理时移除选中或范围终态运行时快照;运行中快照绝不遗忘。
- `lib/pages/transfers_page.dart` / `lib/pages/transfers_page_remote.dart` — 按 活跃/等待/关注/历史 分组显示有效 `RemoteTask` 操作;原始 journal 事件与物理阶段从 `RemoteTaskRow` 展开。legacy `TransferTaskRow` 是无引用兼容代码,不是显示路径。桌面保留上游头部(标题常显、队列标签、分组头)。Android(`_androidCompactQueueHeader`,`defaultTargetPlatform == TargetPlatform.android`)窄屏适配:隐藏队列标签行与列表分组头、选中态标题槽换「已选 N 项」、选中时只保留「清理历史」(立即执行/取消由行内图标承担)、隐藏队列级按钮。`lib/pages/global_trash_page_view.dart` 选中时隐藏「回收站」文字(保留 spacer),仅 Android。`transfers_page_remote_filters.dart` 在 Android 把搜索框叠在两个筛选下拉上。`remote_task_store_polling.dart` 在活跃轮询报告历史增长时自动重载首页;Android **同时**渲染列表内 `_RemoteHistoryPager` 作为显式加载更多入口——自动重载只刷新首页,完成的下载无需翻页即呈现(桌面保持仅 cursor 失效语义)。
- `lib/widgets/batch_task_progress_dialog.dart` — 前台批量(上传/下载/删除)模态进度。汇总 `LinearProgressIndicator(value: progress)`,任何任务 `totalBytes>0` 时 `progress = completedBytes/totalBytes`,全部完成 `1.0`,否则 `null` 不定态。行级确定条仅当 `currentFileTotalBytes>0`。`_modeForTasks` 全部为删除时返回 `BatchTaskProgressMode.delete`;图标在 `lib/widgets/batch_task_progress_mode.dart`。

### Gotchas

- **一个操作恰好一行(binding)。** ID 链:Dart `TransferQueue.startTask` id → 桥接 `upload_file` `taskId` → Go `startTransfer`(同 id)→ 运行时 wire `"transfer:<id>"`(`go/webapi/remote_task_runtime_wire.go`、`bridge/dispatch_remote_tasks.go`),也是 Dart `_publishRemoteTask` 的 key。Metadata worker 物理快照用 `metadata-op-*` id,并被 legacy 队列(`transfer_queue_snapshots.dart`)与两个 `list_remote_tasks` 投影(FFI `bridge/dispatch_remote_tasks.go`、Web `go/webapi/remote_tasks.go`)**过滤**;其进度嵌入持久 `sync:*` 行。破坏任一环(新 ID 前缀、未过滤投影、为 metadata mutation 发布本地行)会重新引入合并前 Android 版「一次上传两行,一行有字节一行没有」的 bug。
- metadata 桶上的页面 mutation 调 `startTask(publishRemoteTask: false)`;本地行只作为进度对话框的执行投影,绝不能进入 `RemoteTaskStore.tasks`。
- 重启直接丢弃持久化 `transfer_queue.tasks.v2` payload(`transfer_queue_storage.dart`):Dart 生产者不能跨进程退出存活,恢复会造出无后端对端的行。
- **下载没有 journal 对应(读不是 mutation)。** 其终态可见性完全依赖 Go 运行时快照行 + 队列增长时的历史自动重载——下载绝不设 `publishRemoteTask: false`,没有其它呈现完成下载的方式之前不要移除该自动重载。
- 选中态头部标题通过在同一 `Expanded` 内把 `Text` 换成 `SizedBox.shrink` 隐藏。不要同时移除 spacer/`SizedBox` 分隔——那会把动作按钮推到左缘,读起来像无关布局变化。
- **PR #5 合并后的 SDK/工具链约束:** `ReorderableListView` 的 `onReorderItem` 参数只在 Flutter 3.47+ 存在;macOS 正典工具链是 3.41.6(`/Users/3000y/development/flutter_3.41.6`,`make run` 使用),`cloud_storage_account_list.dart` 与 `file_manager_bucket_browser.dart` 必须保持经典 `onReorder` 回调直到工具链升级。重新加回 `onReorderItem` 会让本地 `flutter analyze` 失败。`pubspec.lock` 在该合并后于 3.41.6 下解析;3.47 机器可保留这些 pin。
- **Widget 测试平台默认(binding):** widget 测试默认 `defaultTargetPlatform` = **android**,会触发钉住桌面头部行为的测试里的 `_androidCompactQueueHeader`。测试内显式 `debugDefaultTargetPlatformOverride` 并在测试体内 `try/finally` 重置——binding 的 foundation 不变式检查在 `addTearDown` 回调**之前**运行,`addTearDown` 式重置会挂测试。正典示例:`transfers_page_batch_actions_test.dart` 的 `batch cancel from header...`(macOS)与 `android compact header swaps title and hides batch cancel`(android)。
- `totalBytes==0` 的任务渲染不定态(模态)或纯「删除中」文字(传输行);经 `startTransfer`/`AddTransferTotal` + `advanceTransfer` 设置 `totalBytes>0` 立即把模态汇总条与传输副标题变成真实百分比/字节——无需 UI 改动。
