# File Actions — 对象操作、粘贴/拖拽、预览缓存与软删除回收站

## 文件操作与 Linux 挂载所有权

文件管理器的复制/移动选择目标目录而不是要求用户拼对象 key;挂载同时保持跨客户端 metadata 与本地文件系统所有权一致。

页面 mutation 的缓存契约:provider 成功（以及可能留下部分副作用的失败）后，先按源 bucket 失效对象列表缓存，再决定是否刷新可见 UI；每次失效推进 cache epoch，在途请求只有 epoch 未变时才能写回缓存。可见刷新要求逻辑源位置仍是同一 bucket+prefix、非回收站(Android 位置栈、桌面 resume target)，桌面同步 discovery 期另以开始时的 listing generation 作 fence。因而用户离开源目录后再次进入不会命中旧页，A→B 加载期间 A 的晚完成也绝不取消或重载 B，A→B→A 后完成的上传/复制/移动/重命名/删除仍会刷新新的 A；删除完成期间若用户已打开同桶回收站，也不得把页面强制切回对象根。回收站恢复事件也按 bucket 失效所有匹配来源的对象页缓存。

下载命令同样绑定发起时的 source generation：单对象另存为 picker、批量下载的默认目录解析/浏览器准备，以及递归目录 lister 都捕获原始 bucket/config/prefix 和位置请求，并在每个异步等待返回后、首个 provider 调用前再次校验。profile 重绑定或用户离开源目录后，迟到的 picker 结果只会取消本地任务，不会用旧 endpoint/root prefix 发起 listing 或下载；批量流程也不会清除新位置的选区或弹出旧错误。`test/widget_test.dart` 的 Android stale directory-picker 回归锁定该契约。

Android 对象动作抽屉与执行层共用当前目录可写性：`file_manager_page_object_view.dart` 把 `!_currentDirectoryWritable` 传为浏览器 `readOnly`，移动端据此隐藏复制、移动、重命名和删除，`file_manager_page_actions.dart`、`file_manager_page_selected_actions.dart` 与 `file_manager_page_selection.dart` 在执行前再次拒绝写入。批量下载只暴露至少一个可下载条目；浏览器传输和不支持递归目录下载的原生客户端都会过滤目录，即使选择同时包含文件和目录也只建立可用传输。`test/file_manager_object_browser_mobile_test.dart` 覆盖只读抽屉与目录下载入口。

- `lib/widgets/object_action_dialogs.dart` / `lib/pages/file_manager_page_actions.dart` / `file_manager_page_selected_actions.dart` — 复制与移动打开限定当前桶的远端目录选择器,再用 `objectTargetPathInDirectory` 追加每个源对象的显示名;UI 绝不要求用户重建完整目标 key。
- `lib/pages/file_manager_page_uploads.dart` / `file_manager_page_object_deletes.dart` / `file_manager_page_trash.dart` / `file_manager_page_restore_sync.dart` — 上传、删除、回收站恢复和事件刷新落实上述源缓存失效与当前位置刷新契约。
- `lib/services/local_file_opener_io.dart` — Windows 用 `cmd /c start`,路径作为独立 argv 元素,避免 Explorer 文件名查找中的字面引号。
- `go/s3/object_mutations.go` / `object_move_cleanup_test.go` — 重命名与移动删除初始 copy plan 期间捕获的精确源 key,避免延迟重列出把旧对象留在新名旁。
- `go/mount/linux_fuse_nodes.go` / `linux_fuse_owner_test.go` — root 与条目属性用挂载进程 UID/GID,Linux FUSE `default_permissions` 授权桌面用户而不是把远端条目当 root 属主。

回归锚点:`test/object_action_dialogs_test.dart` 验证目录→目标 key 组合;`go/s3/object_move_cleanup_test.go` 验证目录重命名一次规划 listing 并删除每个捕获源 key。Windows 外部打开修复经 `lib/services/local_file_opener_io.dart` 评审,含空格/非 ASCII 缓存路径的应用级检查仍待做。

**Known P2/P3 (review 2026-08-31):** P2 `file_manager_page_preview.dart` 的预览关闭/404 后刷新仍只按 active bucket+prefix 识别桌面源目录；若 A 的预览结束恰逢 B 首屏加载，字段尚未切换时可能发起 A 刷新。后续让 preview 请求校验与 mutation 相同的逻辑源位置（桌面 resume target / Android 位置栈）。

**Gotchas:** Cloud Files 刷新代码只在 `windows && cgo` 构建;macOS/Linux Go 测试验证共享行为但不能执行 Windows CFAPI 调用。改动水合文件、同大小仅 ETag 覆盖、远端删除、占用缓存重挂后,经 Windows 主机的 `scripts/run_windows.ps1` 验证。

## 本地文件粘贴 / 拖拽上传

桌面文件管理页接收本地文件输入(访达复制后 Cmd+V、拖拽到列表)。粘贴走 method channel;拖拽走 `super_drag_and_drop` 的 `DropRegion`。二者共用 `DesktopFileTransferService` 把 file:// URI 解析成本地路径,再交给 `_uploadLocalPaths` 入队上传。

**macOS Cmd+V 的引擎限制(binding 背景):** Flutter macOS 引擎的 `FlutterViewController.performKeyEquivalent` 在 `firstResponder == _flutterView` 时调 `[_flutterView keyDown:event]`;`FlutterView` 是普通 `NSView` 未 override `keyDown:`,默认实现走 `interpretKeyEvents:` 把 Cmd+V 交给 TSM 输入上下文,TSM 静默吞掉 `paste:` selector,事件永远到不了引擎 keyboardManager 或 Flutter `Shortcuts`。因此不依赖 Flutter `Shortcuts` 处理 Cmd+V/C:在 `MainFlutterWindow.performKeyEquivalent`(NSWindow 层)截获并 `return true` 阻止 AppKit 菜单与 TSM,经 `cloud_volume/clipboard_shortcut` method channel 直接通知 Dart。`FileTransferClipboardRegion` 里的 `Shortcuts`/`_PasteFilesIntent` 保留(理论上对非 macOS 或未来 engine 修复有用),macOS 实际由 channel 驱动。

**关键文件:**
- `macos/Runner/ClipboardShortcutPlugin.swift` — `ClipboardShortcutPlugin`(注册 method channel `cloud_volume/clipboard_shortcut`)+ `ClipboardShortcutCoordinator`(单例,持有 plugin 实例供 window 调用)。
- `macos/Runner/MainFlutterWindow.swift` — `performKeyEquivalent` override:Cmd+V → `handlePaste()`、Cmd+C → `handleCopy()`,其余交 `super`;`awakeFromNib` 注册 plugin。
- `lib/services/clipboard_shortcut_channel.dart` — `ClipboardShortcutChannel` 单例:`start(onPaste, onCopy)` 设置 `MethodChannel` handler;`isSupported` 仅 macOS 非 Web。
- `lib/widgets/file_transfer_clipboard_region.dart` — `Shortcuts`+`Actions`+`DropRegion` 包装层(拖拽实际生效;粘贴的 `Shortcuts` 在 macOS 被 channel 旁路)。
- `lib/services/desktop_file_transfer_service_io.dart` — `localFilePathsFromClipboard`(读 `SystemClipboard` 的 `Formats.fileUri`)、`localFilePathsFromDrop`、`writeLocalFilesToClipboard`、`localUploadEntries`。
- `lib/pages/file_manager_page_transfer_inputs.dart` — `_uploadLocalPaths`(入口,含 `_ensureCurrentDirectoryWritable` 兜底)、`_copySelectedObjectsToClipboard`、`_handleNativePaste`/`_handleNativeCopy`(channel 回调入口)。
- `lib/pages/file_manager_page_access.dart` — `_currentDirectoryWritable` / `_ensureCurrentDirectoryWritable` / `_refreshDirectoryAccess`(WebDAV 目录 PROPFIND 可写性检查)。

**数据流:** 访达复制文件 → 系统 pasteboard 含 `public.file-url` → macOS Cmd+V 被 `performKeyEquivalent` 截获 → coordinator → channel `paste` → Dart `_handleNativePaste` → `localFilePathsFromClipboard` 解析路径 → `_uploadLocalPaths` → 可写性校验 → `TransferQueue.startTask` 入队上传。

## 文件预览与上传缓存衔接

点击/双击文件打开走 `FileAccessService._ensureCachedObjectRequest`:`headObject` 拿远端 size/mtime → `FileCacheStore.findUsableCachePath` 经 `RemoteStorageGateway.findCacheIndexRecord` 查 bbolt 缓存索引 → 命中直接用缓存文件,未命中建 `download` 任务拉到 `<cacheDir>/files/<bucket>/<key>` 并写缓存记录。缓存命中硬约束:记录 `localPath` 必须 `_isInsideRoot` 缓存目录内,size/mtime 与远端匹配(`_matchesRemoteObject`)。

**缓存索引持久化在 Go(无前端 SQLite):** 缓存索引经桥接方法 `cache_index_find` / `cache_index_upsert` / `cache_index_remove` / `cache_index_remove_prefix` 存进 Go config bbolt DB 的 `preview_cache` bucket。bbolt key = `bucket + "\x00" + objectKey`,record 字段:`bucket`、`objectKey`、`localPath`、`fileSize`、`lastModified`、`updatedAtEpochMs`。Windows 前端启动不依赖 `sqlite3.dll`,缓存索引 I/O 留在 Go bridge 后台 isolate 调用链。

**预览延迟日志:** 排查点击预览卡顿用 `AppLog.debug` 的 `preview` tag。`lib/pages/file_manager_page_preview.dart` 记录 open/source-load/dialog-close;`lib/services/file_access_service_io.dart` 记录 `ensure start`、`head done`、`cache find done`、`cache path done`、download task create/reuse、cache upsert、download complete、read bytes;`lib/services/file_cache_store.dart` 记录 `cache index find` 与 `cache validate`。日志写入桥接日志(`~/.cloud-volume/runtime/logs/bridge.log`),看 `phaseMs`/`totalMs` 判断卡在远端 head、bridge/bbolt 索引、本地 stat/read 还是下载链路。未手动设置时 Debug 构建默认 `Debug`、Release 默认 `Silent`;release 复现需在 设置→通用→日志设置 切「调试」。

**上传后播种缓存(binding):** 上传走传输队列,成功后只 `markTaskDone` + 刷新列表,从不动缓存表——上传与预览是两套独立记账,不播种就会出现「刚上传完的文件双击还要重下」。修复:上传成功后调 `FileAccessService.seedCacheFromUpload`(io 实现 / Web 空操作):`headObject` 拿远端元数据 → 本地源(`localSourcePath` 或 `bytes`)copy/写入缓存目录 → `upsertCacheRecord`。以远端 size/mtime 为准(不能用本地 stat,否则比对失败)。seed 全程 try/catch 吞异常:只是缓存优化,绝不阻断「上传已成功」;`unawaited` 后台执行不阻塞列表回显。

**关键文件:**
- `lib/services/file_access_service_io.dart` — `seedCacheFromUpload`(桌面)、`_ensureCachedObjectRequest`(预览/打开缓存命中)。
- `lib/services/file_access_service_downloads_io.dart` — part 扩展:下载另存为/默认目录选择,保持主文件行数规则内。
- `lib/services/file_access_service_web.dart` — Web 空操作(浏览器无本地缓存目录)。
- `lib/pages/file_manager_page_uploads.dart` — `_runUploadTask`(本地路径上传,传 `localSourcePath`)、`_runBrowserUploadTask`(bytes 上传)成功分支调 seed，并以捕获的源 bucket+prefix 决定可见刷新。
- `lib/services/file_cache_store.dart` — 缓存路径生成、安全校验、size/mtime 比对、本地缓存文件删除;索引持久化全部委托 gateway 桥接方法。缓存文件本体在 `<cacheDir>/files/<bucket>/<key>`。
- `lib/models/cached_file_record.dart` — Dart 缓存索引记录,JSON 用桥接 camelCase 字段并兼容旧 snake_case 读取。
- `lib/services/remote_storage_gateway.dart` / `remote_storage_api_desktop_cache.dart` / `remote_storage_api_web.dart` — gateway 缓存索引 API;Web 本地缓存索引方法为 no-op/null。
- `go/config/cache_index.go` — Go bbolt 缓存索引 store(复用 `config.db`,bucket `preview_cache`,find/upsert/remove/remove-prefix);`cache_index_test.go` 覆盖读写与前缀删除。
- `bridge/dispatch_cache_index.go` / `dispatch.go` — 桥接 JSON 方法路由。
- `lib/pages/file_manager_page_preview.dart` — 双击预览入口 `_showObjectPreview`。

**数据流:**
1. 预览/打开:`_ensureCachedObjectRequest` → `api.headObject` → `findUsableCachePath` → desktop `cache_index_find` → Go `FindCacheIndexRecord` → Dart 校验路径在缓存根内、文件存在、size/mtime 匹配。
2. 下载或上传 seed 成功:文件写入 `<cacheDir>/files/<bucket>/<objectKey>` → `upsertCacheRecord` → `cache_index_upsert` → Go bbolt `preview_cache`。
3. 删除/移动/重命名对象:`evictCacheForObject` → 文件对象走 `cache_index_remove`;目录对象走 `cache_index_remove_prefix`,Go 返回被删记录,Dart 再清理对应本地缓存文件。

## 对象软删除与应用回收站

从文件管理器删除对象对 S3 账号默认是软删除:对象树被移动(逐条 CopyObject + 逐源 DeleteObject)进桶级回收站前缀,再持久化元数据。UI「删除」因此可能暴露 S3 CopyObject 错误。

### 关键文件

- 删除确认:`lib/pages/file_manager_page_actions.dart`(`_runObjectAction` 删除分支)与 `file_manager_page_selection.dart`(`_deleteSelectedObjects`)经 `showDeleteObjectDialog` / `showDeleteObjectsDialog`(`lib/widgets/object_action_dialogs.dart`;都接 `trashEnabled:` 返回 `Future<DeleteDialogChoice>`,dismiss → confirmed:false)。对话框体是共享 `DeleteDialogBody` StatefulWidget:目标标签 + `ShadSwitch` 永久删除(仅 `trashEnabled` 时,副标签 不移入回收站,删除后无法恢复)+ 取消/破坏性动作;描述按回收站状态切换 移入回收站/此操作不可撤销。然后 `_queueObjectDeletes(permanent:)` + `_showDeleteProgressDialogForTasks`(`file_manager_page_upload_feedback.dart` → `BatchTaskProgressDialog`,`BatchTaskProgressMode.delete`)。
- `lib/pages/file_manager_page_object_deletes.dart` — `_queueObjectDeletes` 启动 `TransferKind.delete` 任务(`localPath: ''`)并跑 `_runDeleteTask` → `api.deleteObject(config, bucket, key, isDir, taskId, permanent:)` + 缓存驱逐 + `markTaskDone/markTaskFailed`;失败收集后经 `_showPageMessage(title: '删除失败', ...)` 呈现(保留 `RemoteStorageBridgeException:` 前缀的原始 `error.toString()`)。
- `lib/services/remote_storage_api_desktop_storage.dart` / `remote_storage_api_web_objects.dart` — gateway `deleteObject` → 桥接 `delete_object`,参数含 `permanent`;gateway 接口声明 `permanent = false` 默认(test fake 必须匹配)。
- `bridge/dispatch.go`(`delete_object` case) — `objectMutationArgs` 携带 `permanent`;handler 在 permanent 时选 `backend.DeleteObjectHard`,否则 `backend.DeleteObject`(进回收站);成功后调 `bucketmount.NotifyExternalDelete`。Web 路径 `go/webapi/invoke.go` 同样路由。回收站操作:`bridge/dispatch_trash.go`(`list_trash`、`restore_trash_item`、`delete_trash_item`、`clear_trash`)、`list_trash_page`(`dispatch_paging.go`)。
- `go/storage/s3_backend.go` — `DeleteObject` 按每桶回收站开关路由:禁用 → `s3ops.DeleteObjectHardContextWithTask`;启用 → `DeleteObjectContextWithTask`(软删)。`DeleteObjectHard` 从文件管理 `permanent` 标志与挂载删除队列可达。`go/config/config.go` `BucketSettingsFor` 对 `StorageTypeS3` 默认 `TrashEnabled=true`,可按桶覆盖(`trashEnabled`、`trashDirectory`);Dart 镜像 `lib/models/remote_storage_config.dart` + `bucket_settings.dart`。
- `go/s3/object_mutations.go` — 软 `DeleteObjectContext(WithTask)` 委托 `MoveObjectToTrashContextWithTask`(`go/s3/trash_ops.go`,taskID 透传)。硬路径:`DeleteObjectHardContextProgress` 经 `mutationEntriesWithProgress`(先报 TotalItems)列条目再 `deleteEntriesHardWithTask`(逐 key 韧性删除 + 每 key `AdvanceTransferItems`),注册任务并转发 taskID,硬删除显示确定条进度条;`DeleteObjectHardContext` 保留零进度路径给内部调用方。
- `go/s3/trash_ops.go` + `trash_helpers.go` + `trash_index.go` — `MoveObjectToTrashContext(WithTask)`:修剪 key、跳过回收站 key、计数、生成 UUID,目标 = `<trashDir>/objects/<uuid>/<originalKey>`(trashDir 默认 `.trash`,可配 `trashDirectoryName`),调 `MoveObjectContextWithTask`(copy + 删源,taskID 转发),然后构建并持久化回收站元数据(`.trash/index/` 下索引对象;legacy `.trash/entries/<id>.trashinfo.json` 回退)。保留期清理:`go/s3/trash_purge_scheduler.go`(10 分钟冷却,`trashRetentionDays` 默认 30 / -1 禁用)。
- `go/s3/object_moves.go` `MoveObjectContextWithTask` — 有 taskID 时经 `mutationEntriesWithProgress` 预报 TotalItems(单次枚举被 `buildObjectTransferPlan` 复用),然后 `executeObjectCopyPlan`(`object_transfer_run.go`:逐条韧性 CopyObject,占位符变 PutObject 标记,`advanceTransferTaskProgress` 每条推进字节 + item),最后对 `plan.deleteKeys` 跑 `deleteObjectKeysHardWithTask`(item 计数越过 copy 总量继续推进,回收站移动条跑满 copy item 的 200% = 整体 100%)。字节进度经 `beginObjectTransferTask`。`plan.deleteKeys` 在 plan 构建时捕获(`object_transfer_plan.go` + `object_entries.go` 的 `transferEntryKeys`);`listMutationEntries` 还调 `ensureDirectoryRootEntry`,provider 列子项时省略源 `dir/` 标记也不会在重启后留下空目录。清理**不得**重新列源前缀——重列会观察到中途已删 key 并静默跳过,留下过期源对象。`object_move_cleanup_test.go` 覆盖捕获 key 集与省略根标记响应。
- `go/s3/object_transfer_progress.go` / `object_delete_progress.go` / `object_entries.go` / `transfer_phases.go` — 字节总量、逐条推进、逐项删除进度、阶段感知 item 计账(同一清扫的 copy 与 delete 阶段不重复计数不越界)。item 字段经 `TransferSnapshot.totalItems/itemsCompleted` → `TransferTask` → `BatchTaskProgressDialog`(totalItems>0 时确定汇总条、`x / y 个对象` chip、清理阶段行副标题 正在删除源对象;传输页 `_subtitleFor` 同计数)。测试 `go/s3/transfer_phase_plan_test.go`。
- Flutter 回收站开关:`lib/models/remote_storage_config.dart` `bucketSettingsFor`(`defaultTrashEnabled = storageType == StorageType.s3`)/ `bucketTrashEnabled`;`lib/models/bucket_settings.dart` `isTrashEnabled`。文件管理:`file_manager_page_bucket_policy.dart` `_bucketTrashEnabled` / `_activeBucketTrashEnabled` 决定删除对话框开关可见性。编辑 UI:`lib/widgets/bucket_settings_dialog.dart`(ShadDialog 内 ShadSwitch)。
- `go/s3/client.go` — 单一 `s3.New(opts)` 客户端:静态凭证、`Region`、`BaseEndpoint=cfg.Endpoint`、`UsePathStyle`、仅 direct/custom 时覆盖代理。全局客户端保持 AWS SDK v2 默认重试(3 次);清扫调用点选择更大每调用预算。
- `go/s3/aws_retry.go` + `object_copy_retry.go` — 单对象清扫调用(CopyObject、HeadObject、DeleteObject、占位符 PutObject)的每调用重试层。`singleObjectCallOptions()` 给个别 API 调用挂标准 retryer(5 次 / 15 秒最大退避,不挂客户端);其上 `runSingleObjectSweep` 对 vendor-flaky 不可重试错误(`isSweepWorthyError`:InvalidArgument/InvalidRequest、非可重试 5xx 码、传输错误)额外重发最多 3 次、2 秒延迟(测试经 `singleObjectSweepRetryDelay` 缩短)。删除清扫走 `object_delete_sweep.go` `deleteObjectKeysHard`;copy 清扫走 `object_transfer_run.go` 的韧性变体;plan 体积走 `object_transfer_plan.go` 的 `headObjectResilient`。测试 `object_copy_retry_test.go`。

### Gotchas

- 软删除逐对象移动;目录删除时整棵树先拷进回收站再删源——大目录删除 = N 次 CopyObject + N 次 DeleteObject,任一 copy 失败整体失败。每调用重试吸收瞬态网关错误(502 HTML 页、连接重置、vendor InvalidArgument),持续故障仍以原始 SDK 错误中止并显示在 删除失败 对话框。
- 部分 S3 兼容服务在有子项后从 `ListObjectsV2` 省略精确目录标记。**绝不**把裸递归 listing 当目录 mutation plan:`ensureDirectoryRootEntry` 刻意补 `dir/`,使目标占位符创建与幂等源标记删除成为 copy/move/软删/硬删的一部分。
- 永久删除 对话框开关只在桶启用回收站时出现;桥接侧强制(`permanent` → `DeleteObjectHard`),Dart 标志是建议性的。回收站禁用的桶不显示开关(其删除本来就是永久的)。
- 删除任务进度是 item 基(TotalItems/AdvanceTransferItems),不是字节基:模态汇总条优先 `totalItems > 0`。item 计账阶段感知:回收站移动从源 listing(最坏情况)规划 delete 阶段、从目标树枚举规划 copy 阶段;相同重枚举替换而不是重复计数。copy 与源清理之间,`MoveObjectContextWithTask` 调 `resetTransferPhaseItems` + `SetTransferStatusDetail(taskID,"deleting")` 使进度条在删除阶段从 0/N 重启。`finishTransfer` 结清 ItemsCompleted=TotalItems,完成任务绝不出现 206/103 越界。
- `RestoreTrashItem` 从回收站 key 拷回原 key;`DeleteTrashItem`/`ClearTrash` 硬删回收站载荷。
- 文件管理页无持久内联传输托盘:删除反馈只有模态 `BatchTaskProgressDialog`;行内反馈是 `deletingKeys`(`_deletingObjectKeys` → `FileManagerObjectBrowser`);之后完成/失败状态只在传输页。
- 挂载删除队列(`go/mount/delete_queue.go`)也调 backend `DeleteObject`/`DeleteObjectHard`,把 `CopyObject`+`InvalidArgument` 错误当不可重试。
- 回收站 UI:文件管理头部回收站图标(`lib/widgets/file_manager_action_bar.dart`,由 `_activeBucketTrashEnabled` 门控)、每桶回收站浏览器 `file_manager_trash_browser.dart`、全局页 `lib/pages/global_trash_page.dart` + `global_trash_browser.dart`、设置区 `settings_trash_section.dart`、侧栏入口 `main_layout_page.dart`。
