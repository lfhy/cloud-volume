# Mount External Sync — 外部失效与远端轮询

## 挂载缓存外部失效

文件管理界面的删除/重命名/移动/复制/建目录/上传经 bridge/webapi 直接改远端对象,绕过 `go/mount`。为了让挂载点(Finder/WebDAV/FUSE)与文件管理列表不显示幽灵文件、不卡「删除中」,所有外部 mutation 成功后必须同步失效挂载 session 的 `bucketCache`。

### 关键文件

- `go/mount/external_invalidation.go` — 导出 `NotifyExternalDelete`/`NotifyExternalUpload`/`NotifyExternalRename`,委托 `globalManager.notifyExternalMutation(cfg, bucket, callback)`。session 不存在或 cfg 不匹配时 callback 不执行,无挂载场景零开销。
- `go/mount/bucket_access_reads.go` — `bucketAccess.MarkExternalDelete`(`markDeleted` + `invalidatePath`,放 tombstone)、`InvalidateExternalUpload`(`removeLocalPath` + `invalidatePath` + 父目录,清 tombstone/staging)、`InvalidateExternalRename`(= 删旧 + 传新)。
- `bridge/dispatch.go` — `deleteObject`/`renameObject`/`createDirectory`/`uploadFile`/`uploadDirectory` 成功分支调 `bucketmount.NotifyExternal*`;`parentDirectoryOf`/`joinChildPath` 辅助计算路径。
- `bridge/dispatch_object_transfer.go` — `copyObject` 调 `NotifyExternalUpload(TargetKey)`;`moveObject` 调 `NotifyExternalRename(SourceKey, TargetKey)`。
- `go/webapi/invoke.go` — webapi 同名 mutation 同步接入(`delete_object`/`rename_object`/`copy_object`/`move_object`/`create_directory`),仅在 `err == nil` 时调用。
- `go/mount/external_invalidation_test.go` — 覆盖 delete/upload/rename 对 `listCache`/`objectCache`/`localEntries`/`deletedPaths` 的失效,以及 cfg 不匹配/无 session 时的 no-op。
- `bridge/dispatch_metadata.go` / `dispatch_paging.go` / `go/mount/object_page.go` / `object_page_snapshots.go` — 有 `ProfileID` 的桌面页面分页、旧 `list_objects` 与 `head_object` 都走 metadata inode 树,游标是持久目录 revision + nameKey;不探测挂载会话,不生成 `m:<snapshot-id>`。`ListMountedObjectPage` 与 2 分钟快照仅为无身份 legacy 挂载保留。Web API 仍是 provider-direct 的独立 P2 transport。
- `lib/pages/file_manager_page_object_deletes.dart` — 删除 API 成功后立即从 `_objects`、`_selectedObjectKeys`、`_deletingObjectKeys` 移除该 key;批次结束时把成功 key 传给写后刷新,失败 key 恢复成普通可操作行。
- `lib/pages/file_manager_page_object_loading.dart` — `_loadObjects(... suppressObjectKeys:)` 过滤本批次已确认删除、但提供方短暂重新返回的旧 key,并丢弃对应原始页缓存,让后续导航重新请求后端。
- `test/file_manager_delete_state_test.dart` — 回归覆盖「删除成功但 force-refresh 仍返回旧目录」,确保行与删除标记都收敛。

### Gotchas(binding)

- `InvalidateListCacheForPrefix`(仅清 `listCache`)不足以反映外部变更——`mergeLocalFiles` 会用过期 `localEntries` 把幽灵塞回列表,`hiddenByDeleteLocked` 也会用过期 tombstone 隐藏本应显示的对象。外部 mutation 必须用 `NotifyExternal*` 的完整语义(同时清 `objectCache`/`localFiles`/`localEntries`/`deletedPaths`)。
- 不要只依赖 `_deletingObjectKeys.removeWhere((key) => !visibleKeys.contains(key))` 收敛状态:S3/挂载刷新可能短暂返回旧目录,成功任务永久显示「删除中」。删除 API 成功必须主动清 key/移除行,随后的写后刷新再用成功 key 抑制一次陈旧响应。
- `uploadDirectory` 是 `go func()` 异步:启动时先 `NotifyExternalUpload(parentDirectoryOf(Key))` 让父目录可见,goroutine 完成后再 `NotifyExternalUpload(Key, isDir=true)` 刷新目录内容。

### 数据流

1. 界面操作 → bridge `delete_object` 等 → `storageops.ForConfig(cfg).XxxObject(...)` 改远端。
2. 成功后 bridge 调 `bucketmount.NotifyExternal*(cfg, bucket, path, isDir)` → `globalManager.notifyExternalMutation` → 匹配 session → `bucketAccess.MarkExternalDelete/InvalidateExternalUpload/InvalidateExternalRename`。
3. Flutter 收到删除成功后立即移除行与「删除中」标记;批次 `list_object_page(forceRefresh)` 用成功 key 过滤一次陈旧响应并丢弃该页缓存。挂载点下一次 `listDirectory` 重新 `fetchDirectory`,tombstone/远端结果共同隐藏已删 key。

Windows Cloud Files 侧的物理投影(placeholder 删除/重建)见 [windows_platform](windows_platform.md) 的 Cloud Files 外部删除投影一节。

## Mount Remote Polling P0

P0 是多客户端挂载变更发现的无服务兜底:只刷新用户近期打开的目录,远端对象存储仍是唯一字节与版本权威。

- `go/config/config.go` / `go/config/config_account.go` / `lib/models/remote_storage_config.dart` / `remote_storage_config_copy.dart` — `mount_remote_poll_seconds` / `mountRemotePollSeconds` 是 P0 活跃轮询间隔(默认 5 秒,后端归一化到 1–300 秒);账户辅助方法与 Dart 不可变 `copyWith` 各自拆文件,避免配置模型超行数限制。
- `lib/pages/settings_page.dart` / `settings_page_poll_actions.dart` / `settings_page_sections.dart` / `lib/widgets/settings_sync_section.dart` / `lib/pages/config_setup_page.dart` / `lib/pages/config_setup_save.dart` — 「同步设置」保存 P0 远端目录轮询间隔;首启页由独立 save part 在配置编辑时保留该值;保存后重新挂载,新会话才采用该间隔。
- `go/mount/remote_poller.go` — `directoryActivityTracker` 在 `bucketAccess.listDirectory` 与 Cloud Files placeholder 回调中记录目录活动,保留上限 12 个目录(`remotePollDirectoryCap`),新目录活动时唤醒等待中的 poller。空闲条目不再被 warm window 删除;满了逐出最旧,`nextDelay` 作为节奏选择器(45 秒内活跃按 `mount_remote_poll_seconds` 刷新,45 秒–3 分钟 warm 间隔,之后两分钟空闲节奏)。3 分钟无活动目录时停止网络访问。它调 `fetchDirectory` 刷新 `bucketCache`,绝不用远端状态删除本地 overlay 或 writeback。
- `go/mount/manager.go` / `go/mount/types.go` — 每个成功启动的 `mountSession` 创建 poller;卸载先停止轮询再关闭平台后端,避免访问已释放的 `bucketAccess`。
- `go/mount/backend_windows_cloud_files_cgo.go` / `cloud_files_hydrator_windows.go` / `cloud_files_refresh_windows.go` — P0 轮询结果经 `externalDirectoryRefresh` 进入 `RefreshPlaceholders`。它记录已投影目录的远端快照:新对象创建占位符,已存在对象经 `CfUpdatePlaceholder` 更新元数据并对变更文件脱水,远端删除只移除之前投影且无本地写回/tombstone 的项。对象 ETag 参与文件标识,同大小同秒覆盖也会失效 Explorer 缓存。
- **Metadata 缓存独立性:** 禁用挂载 metadata 缓存持久化 `MountMetadataCacheSeconds = -1`;`newBucketAccess` 把它转换为零 `bucketCache` TTL,但 `allowRemotePoll` 独立于后端能力判断。`pollRemoteDirectory` 仍调 `fetchDirectory` 与 `externalDirectoryRefresh`(即使 `cache.storeList` 成为 no-op),Windows Cloud Files 占位符刷新不依赖 metadata 缓存开启。metadata 缓存与轮询间隔改动都只对新挂载会话生效;改任一设置需重挂。有共享 poller 单测与 Windows metadata 比对测试,但该缓存禁用组合没有自动化真实 CFAPI 测试。
- `go/mount/remote_poller_test.go` / `object_page_test.go` — 覆盖远端目录缓存刷新、占位符投影回调、活动/空闲退避窗口、目录写入期间的稳定快照分页。

**Gotchas:** P0 不是文件传输协议,也不是递归扫描器。不保证即时投递,未主动刷新的文件管理器窗口可能仍需一次目录读取;删除与覆盖投影只作用于自己此前记录的远端占位符,必须跳过 tombstone、排队写回、正在上传的路径,不能盲目删除本地项。
