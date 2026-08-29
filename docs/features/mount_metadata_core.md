# Mount Metadata Core — 持久 inode 元数据与统一读写视图

应用正朝「一个持久 inode B+Tree 元数据视图 + 操作 journal,Flutter 文件管理器与挂载后端共用,远端同步由 journal 驱动」重构。当前状态:持久 inode 元数据支撑页面/挂载读取与 metadata 写入,统一 `RemoteTask` 投影是唯一远端操作 UI 来源;挂载与 profile 域页面 mutation 共享同一 journal-first 命名空间,没有持久 `ProfileID` 的调用方仅保留 legacy 执行兼容。设计全文见 [MountMetadataJournalPlan.md](../MountMetadataJournalPlan.md);架构决策及放弃的替代方案见 [journal-first 决策记录](../notes/implemented/architecture/2026-08-17-journal-first-metadata-core.md)。

## 架构不变式(binding)

### 1. 单一事实来源:挂载与页面共享一个 inode 视图

- Flutter 文件管理器(`listObjectPage`、`headObjectFromMetadata`)与每个挂载适配器(`webdav_file`、`linux_fuse_file`、`winfsp_fs_windows`、`cloud_files_hydrator_windows`)的列表、stat、字节读取必须经同一个 bbolt 支撑的 `metadata.Service`。重新引入「挂载读缓存、页面读 provider」的分裂即回归,即使可见行为碰巧一致。
- 从 metadata service 之外读写持久状态的新入口,只有在对应 Code Map 条目(`docs/features/*.md`)写明理由并有测试证明两个表面看到同一变更时才允许。
- 文件管理页在影响当前前缀的 metadata 任务到达终态时必须强制刷新列表;机制是 `RemoteTaskStore` + `_refreshOnMetadataTaskCompletion`(`lib/pages/file_manager_page_restore_sync.dart`),不要按调用点重新实现。
- `Manager.Acquire` / `Manager.AcquireWithBackend` 是获得 metadata 句柄的唯一合法途径;对有 `ProfileID` 的 profile 回退到 provider 直读等价于上述分裂回归。
- 挂载写路径(`createDirectory`、`stageLocalWrite`、`rename`、`delete` in `metadata_write.go`)必须走 `Service.WritePath` / `EnsureDirectoryPath` / `DeletePath`。绕过 journal 的本地-only 写回是临时脚手架,不是设计。
- `TransferQueue` 只是执行/本地生产者兼容门面,绝不是显示来源。Go 侧统一 `RemoteTask` 投影是任务页、侧栏、同步卡、预览、批量对话框、更新进度的唯一显示来源(详见 [remote_tasks](remote_tasks.md))。

### 2. Metadata 持久化契约

- metadata journal 是所有本地 mutation 的唯一持久来源。任何 mutation 在其 journal 条目提交进 `ready_ops`(inline 写则直接进 `journal`)之前不得触达 provider。
- 磁盘上的 chunk 必须 fsync 并原子重命名进 `chunks/<hash[:2]>/<hash>` 之后,指向它的 `ContentRef` 才能进入 bbolt;反向同理:退役 `ContentRef` 必须递减每个 chunk 的 `nlink`,仅当 `nlink == 0` 才删文件。两个方向的桥都是 `chunk_store.go` / `chunk_protection.go`;worker、挂载、页面代码不得绕过。
- 保护 manifest 是缓存清理的唯一权威。缓存清理(`go/config/cache_maintenance.go` / `metadata_chunk_cache.go`)必须拒绝删除有效 manifest 中列出的 chunk 或活跃 splice 文件,且把缺失/损坏的 manifest 保守地当作「该命名空间全部 chunk 受保护」;清理动作报告 `skippedProtected`,缓存统计暴露 `protectedBytes`/`protectedFiles`,Dart 缓存模型反映同一规则。
- Worker claim/execute 轮次在后台循环与 `Drain` 之间串行;已 claim 的轮次必须在同一锁下跑完,不许新 claim 插入。Worker 重试期限、依赖谓词、命名空间静默屏障是持久不变式——不得为「让 flaky 测试通过」而弱化。
- verifying / cancel-requested / reconciling 状态在启动时恢复并探测;已触达 provider 的副作用绝不能对其 pre-side-effect 指纹重放。这是 post-upload-verification-timeout 测试钉住的行为。
- Reset/rebuild 只在 `Status.PendingOps`、`Status.FailedOps`、`Status.PendingContent` 全为零时才原位擦除 bbolt。Pending content 与 pending ops 是受 reset guard 保护的数据级状态,本开发阶段禁止在其上重建。
- Schema 不匹配返回错误,没有原地升级;bump schema 版本并从 provider listing 重建命名空间。`schema.nextOpSeq` 保证序列在历史压缩后仍单调;复用序列号是 bug。
- 崩溃恢复不变式:
  - 没有被 admitted `ContentRef` 引用的 chunk 是孤儿块,`chunk_recovery.go` 启动时删除。
  - 无写/重命名属主的 `AwaitingJournal` ref 启动时移除,安全时其新 pending inode/dirent 也一并清理。
  - `OpStateRunning` 重启时重置为 `Pending`;`Verifying` / `CancelRequested` / `Reconciling` 保留并重新探测。

## Manager 与命名空间注册表

- `go/mount/metadata/manager.go` — 命名空间注册表,根在 `RuntimeDir()/metadata/v1/<namespace-hash>`;namespace = `ProfileID + storageType + endpoint + config bucket + rootPrefix + bucket`。跨挂载会话保留 Service+Worker,`DrainAll` 并发排空所有命名空间 worker,应用退出耗时 = 最慢 worker 超时而非总和。`DefaultManager` 进程级共享,页面与挂载调用方共用命名空间生命周期;生产 `Acquire` 为 `storage.scopedBackend` 保留 `RootPrefix`,metadata 路径保持视图相对。无不可变身份的 config 返回哨兵 `ErrNoProfileID`(不是 formatted error),调用方据此走 direct-listing 回退。`AcquireWithBackend` 是注入/测试变体,`RemoveAllForTest` 为测试辅助。未引用的命名空间在 `Status` 报告 pending/failed 操作或 pending content 时保持存活——这让逐请求页面句柄安全:后台 worker 在工作排空前可用,之后的 acquire/release 修剪空闲 service。`Op.HardDelete` 持久化,worker 执行为永久页面意图选择 `DeleteObjectHard`。
- `go/config/config.go` + `go/config/config_db.go` + `profile_identity.go` — 不可变 `RemoteStorageConfig.ProfileID`,每 profile 生成一次并在保存/重命名后保留,metadata 命名空间因此稳定。`loadProfileFromDB` 以写事务运行并在读取时惰性回填 `ProfileID`,legacy 迁移 profile 不再使用不稳定 `unversioned-*` 身份。
- `go/mount/metadata/metadata_test.go` — 钉住跨 listing 稳定 inode 身份、rename 不重写后代、祖先环拒绝、stale-cursor 重载、只读拒绝、reset guard 强制语义、命名空间确定性。

## 持久元数据核心

- `go/mount/metadata/types.go` — 持久契约:`Inode`、`Dirent`、`Op`、`ListingState`、`ContentRef`、`Object/Page/Cursor`、`Namespace`、窄 provider `Backend` 接口。`ContentRef` 持有序 SHA-256 chunk 哈希,从不存本地路径;move 在首个副作用前冻结 provider `MoveSource`/`MoveTarget` 及目标边。`Namespace.CacheRoot` 把 chunk 数据与运行时元数据 DB 分离。Inode 身份仅在每个命名空间内局部;无 symlink/hardlink。
- `go/mount/metadata/store.go` / `store_io.go` — bbolt schema v5:`schema/inodes/dirents/journal/listing_state/content_refs/chunks/ready_ops/inode_ops/task_groups/task_members`;`schema.nextOpSeq` 在历史压缩后保持 journal 序列单调。Root inode 固定为 1;inode 单调分配永不复用。写全串行;schema 不匹配返回错误(reset/rebuild,无升级)。
- `go/mount/metadata/service_read.go` — `MaterializeDirectory`、`ListPage`、`StatPath`、`StatInode`、`Resolve`、`Path`。分页游标是 base64url `{v,inode,revision,lastNameKey}`;目录 revision 变化返回 `ErrStaleCursor`,UI 重载而非假装快照一致。Pending rename 源与 tombstone 抑制其过期远端 key。已重命名目录通过其确认的 Remote 边列出,同时保留物化的子 OID,即使其 Desired 名已更新。
- `go/mount/metadata/service_directory.go` — 路径级 `ListDirectory` / `RefreshDirectory`(挂载适配器用),内部解析/物化 inode 路径并枚举完整 B+Tree 目录,不泄漏 root inode 常量或 UI 分页游标。`service_read.go` + `keys.go` 在声称单层 listing 中拒绝深层 provider key,而不是把 basename 平铺进错误 inode。
- `go/mount/metadata/write.go` / `write_stage.go` — Desired-tree 写入:`CreateDirectory`、`StageWrite`(固定 4 MiB 分块、SHA-256、fsync + bbolt ref 提交前原子重命名)、`Write`、`Rename`、`Delete`。chunk 分块前先持久保留一个零写 generation,快速连续路径写拥有不同 `ContentRef` key。`write_stage.go` 在 staging 或 journal 追加失败时回滚新 inode/ref;启动恢复移除崩溃后没有 journal 属主存活的 `AwaitingJournal` ref。Root rename/delete 拒绝。Rename 精确改动两个 dirent B+Tree + 一个 inode 边;后代 inode 与内容文件不动。
- `go/mount/metadata/service_write_path.go` — 挂载/页面路径门面:`CreateDirectoryPath`、`WritePath`、`RenamePath`、`DeletePath` 先解析 Desired 路径再调 inode API。门面串行化自身路径 mutation,并把 staged generation 绑到匹配的写 journal 条目。
- `go/mount/metadata/service_write_path.go` / `metadata/write_path_fast.go` — profile 域路径写先 stage 受保护的内容寻址 chunk,再在**一个** bbolt 事务里提交 inode、generation、chunk nlink、`ContentRef` 与 journal 索引,取代旧的 ensure-inode/reserve-generation/ref/write 序列,同时保留精确 generation 的 worker 退役与崩溃清扫。
- `Op.ContentGeneration` 把写与本地-only rename 物化绑定到精确 `ContentRef`,快速连续写各自退役自己的 generation,而不是把最新 staged ref 上传两次留下卡死的后续 op。
- 首个 chunk root 持久化在 `schema.chunkRoot`;之后修改配置的缓存目录不会搁浅 pending 数据。重开的 service 与 RemoveNamespace 使用持久 root,直到未来的显式迁移。
- `go/mount/metadata/chunk_store.go` / `chunk_protection.go` — pending 数据面:chunk 位于 `<CacheDirectory>/metadata-chunks/<namespace>/chunks/<hash[:2]>/<hash>`;`chunks[hash]` 有逻辑 `nlink`、size、last-access。StageWrite 在 bbolt 前写/sync chunk、去重相等块,并在 ref 提交前把每个前瞻 hash 原子发布进 `protection.json`,并发缓存清理不会删掉多块写中较早的块。每个新 chunk 在 bbolt admission 前 fsync 文件与最终 hash 目录;可恢复的 tmp 源目录 sync 与 staging 后冗余的前瞻 manifest 写刻意省略。Worker 上传用临时完整文件拼接;退役/删除递减 ref、移除零链接块。启动清扫移除未提交孤儿 chunk 与中断的 splice 文件。保守的命名空间保护 manifest 在爆发开始时 fsync 一次、250ms 空闲后 finalize;有效 manifest 与活跃 splice 文件始终受缓存清理保护,service close 阻止延迟 finalizer 触碰已关闭的 bbolt 句柄。
- `go/mount/metadata/chunk_recovery.go` — 启动对账:移除无写/重命名 op 属主的 `AwaitingJournal` chunk ref,安全时删除其新 pending inode/dirent,然后清扫孤儿块与中断上传文件。低层裸 `StageWrite` ref 为有意单独追加 op 的调用方保留。
- `go/mount/metadata/status.go` — `Status` 额外计数 `PendingContent`;status 与 reset guard 扫描 journal,running op 离开 `ready_ops` 后仍受保护。Reset 取 Service 操作屏障,原位重建 bbolt(而非关闭/换句柄),然后清扫分离的 chunk root;强制 reset 等待 in-flight worker 再重建。
- `go/mount/metadata/worker.go` / `worker_execute.go` / `worker_move.go` / `worker_reconcile.go` / `status.go` — scheduler/executor 分离:静默期 journaling、重试退避(15s→2m)、pre-upload 指纹检查、有界 provider 确认(45s 期限)、确认、冲突标记、命名空间限定传输快照 ID `metadata-op-<namespace>-<seq>`、基于探测的取消对账。verifying/cancel-requested/reconciling 状态建索引且启动恢复;post-side-effect 验证错误把 op 留在 `verifying` 走探测对账,而不是对旧指纹重放覆盖。取消仅在 provider 缺席或显式补偿 move/delete 验证后才终态化。写针对其不可变 journal parent/name Remote 边执行,之后的 rename 再移动它;move source/target 与确认 parent/name 在 provider 调用前冻结,后续 Desired rename 不能重定向重放。目录 move/delete 等待更早的后代工作。worker claim-and-execute 完整轮次在后台循环与 `Drain` 之间串行,保留替换的 delete-before-move 顺序;`Drain` 用非阻塞 pass-gate 尝试,轮询工作活跃时 context 保持响应。`claimDue` 还在同一 inode 与先前父工作、命名空间级本地 mutation 静默屏障上等待共享的未决状态谓词,递归 Finder 拷贝保持本地而新 journal 操作持续到达。`Drain` 只绕过瞬态屏障,重试期限与依赖仍然生效。`SkipQuiet` 是手动 trigger/retry 的持久 one-shot 标志,被 claim 时清除;pending 时间戳在重启后重建屏障。删除清除已确认子树。`remoteTarget` 仅对从未同步的 delete 回退到 Desired。
- `go/mount/metadata/status.go` / `worker_move.go` / `tasks_control_rollback.go` — 确认把非空 provider `HeadObject.LastModified` 持久化进 `Inode.RemoteMTime` 与可见 `Inode.MTime`,除非更新的本地时间戳属于更晚的未决写。Pending 物化单独保留远端值,取消在释放更新的 staged 写后原子恢复它。新建 SFTP 目录的时间戳因此同步后立即可见,而较旧的确认不会覆盖快速后续写、后续取消不会保留被丢弃的本地时间;`worker_mtime_test.go` 钉住三种情形,`sftp_backend_test.go` 钉住 SFTP `Stat` 来源。目录物化仍是远端时间戳的 listing 路径来源;Dart 浏览器端只对真正为空的值留白。
- `go/mount/metadata/service_directory.go` + `webdav_fs.go`(M3 局部)— 无确认 Remote 边的 Desired 目录在 mkdir worker 完成前是本地权威:路径解析、显式刷新/轮询、WebDAV 递归 Finder `MKCOL` 序列都不会对未创建父目录发 SFTP `ReadDir`(那会变成 HTTP 409 与误导性的 macOS「无效名称」弹窗);协议与服务回归覆盖嵌套创建与强制刷新。`service_write_path.go` / `metadata_write.go` / `status.go` / `worker_execute.go` / `webdav_copy_test.go` — 挂载 MKCOL 用 `EnsureDirectoryPath` 在 Finder 乱序发嵌套目录创建时本地物化缺失的 Desired 祖先;绝不列出未确认的远端父目录。Pending 子 mkdir 保留当前本地名用于 pre-execution rename 折叠,但通过确认的 Remote 边解析父目录,更晚的祖先 move 不能把它们重定向进该 move 正在等待的 provider 目录。`go/storage/webdav_backend.go` 对 href 路径只解析一次(保留字面 `+` 与编码 percent 序列),不应用 query-form 解码。
- `go/mount/metadata/subtree.go` — `collectSubtreeInodes` 沿 `DesiredParentID` 链找目录全部后代(visited 标记已检节点;损坏父边传播错误而不是静默跳过)。`purgeInodeRecords` 删除 inode 记录、content ref 与每目录 `dirents` 子桶。覆盖:`subtree_test.go`(子树清除、依赖阻塞、崩溃/重放、pending 子保留)。
- `go/storage/sftp_backend_listing.go`、`ftp_backend.go`、`webdav_backend.go` 把 provider mtime 归一化为客户端 `time.Local` 墙钟 `ObjectInfo.LastModified`(SFTP 只给 epoch,无服务端时区元数据);`go/mount/object_time.go` 用 `time.ParseInLocation(..., time.Local)` 恢复,WebDAV/Linux FUSE、Cloud Files、WinFsp 都用它而不是 `time.Parse`(后者静默按 UTC)。Flutter 与 metadata 原样透传归一化字符串。`object_time_test.go`、`webdav_dir_mtime_test.go` 钉住 UTC+8 行为。Known P2:FTP 客户端库仍把无时区的 legacy `LIST` 日期当 UTC;标准 MLSD/MLST 时间戳是绝对的,但精确支持非 UTC legacy FTP 服务器需要显式服务端时区设置与集成 fixture。
- `go/mount/metadata/tasks.go` / `task_types.go` / `tasks_index.go` / `tasks_control.go` / `tasks_control_rollback.go` / `tasks_control_content.go` / `manager_tasks.go` — schema-v5 持久任务投影:稳定 `sync:<namespace>:<group>` ID、混合生命周期段的序列限定 ID、pre-execution mkdir/rename 链折叠、连续 rename、同 inode 快速写,保留原始 journal 事件、依赖原因与全部命名空间限定物理快照 ID;`tasks_control*` 提供事务性取消回滚、重试/触发、`cancel_requested`/`reconciling` 状态、单调历史压缩与压缩后严格任务组查找。任务投影与排序契约详见 [remote_tasks](remote_tasks.md)。

## M2/M7:页面读路径走 metadata(已完成)

- `bridge/dispatch_metadata.go` — `list_object_page` 路由进统一 inode 视图,并暴露配套 `headObjectFromMetadata` 适配器。二者经 `metadata.DefaultManager().Acquire` 获取命名空间、解析 desired 路径,仅在 `ErrNoProfileID` 回退;持久身份的 manager/acquire 错误 fail closed,不开第二视图。`objectInfosFromWire` 让 legacy `list_objects` 保留输出形状同时读同一 metadata 页。`forceRefresh` 触发 `MaterializeDirectory`;`ErrStaleCursor` 让页面重启直到 Dart 学会显式重载信号。还暴露 `metadata_namespace_status` 返回 `Service.Status()`。
- `bridge/dispatch_paging.go` — `listObjectPage` 顺序:有 `ProfileID` 的 config 走 metadata 命名空间;否则 legacy `ListMountedObjectPage`,再 provider 直连。profile 域页面绝不探测挂载会话存活,也不会收到进程局部 `m:<snapshot>` 游标。
- `bridge/dispatch.go` — 注册 `metadata_namespace_status`。
- `bridge/dispatch_metadata_test.go` + `dispatch_metadata_fake_backend_test.go` — 钉住:无 ProfileID 回退、wire 适配形状、stale-cursor 解包、forceRefresh 重物化(缓存视图 vs 强制视图 vs 远端变化),通过内存 `metadata.Backend` fake。
- `lib/models/remote_storage_config.dart` / `remote_storage_config_copy.dart` — Flutter 在 JSON 与 `copyWith` 保留 Go 不可变 `profileId`,桌面页面请求把它发回桥接并激活 metadata 路径。字段对未保存/内存 legacy config 可选,仍有意走 direct-listing 回退。
- **M7 验收:** `go/mount/metadata_shared_view_test.go` 从同一 manager 持有页面与挂载句柄,证明 pending mkdir/write/rename/delete 共享一个 Desired 视图。`mvp_recovery_test.go` 钉住 reopen-before-worker 与强制 reset 重建行为。
- **Known P2/M2-M7(review 2026-08-17,详见 [PROJECT_GUIDE](../PROJECT_GUIDE.md)):** 每页 Acquire/Release 翻动 worker/db 生命周期;`ListPage` 只返回直接子项(不同于旧 S3 flat-prefix listing 含深层 key);指向前缀是文件时报错而非列出;页面句柄生命周期后续移到会话域。
- **M3 生命周期守卫:** `newBucketAccess` 为任何有 `ProfileID` 的 config 保留 `metadata.AcquireHandle`,从 `close()` 和 `release()` 幂等释放,页面请求不会关闭活跃挂载的 worker/DB。仅缺 `ProfileID` 保持 legacy 回退;其它 acquire 错误使挂载启动失败。平台 `Start` 部分成功留下活跃挂载但清理 `Stop` 被拒时,该会话保留在 manager 中,其 queue/namespace 可达以供稍后重试。`Service` 静默/只读策略与 scoped provider transport 同步并在两个 `Manager.Acquire` 路径刷新;一个 worker 操作只捕获一次 backend 用于 mutation 与确认,下一个操作使用刷新后的凭证/token/代理。pending 读集成仍必须把 metadata 当远端基座:物化前合并系统 overlay 与 tombstone,再本地文件/目录、恢复或排队写回、`dirSync` 条目。挂载 backend 刻意不 scoped,metadata 物化必须用其 scoped provider。Legacy-only 写在 M6 前仍绕过 Desired/journal。

## M3:挂载读集成(已完成)

- `go/mount/metadata_read.go` — metadata `Object` 适配 `s3ops.ObjectInfo`,在 `metadataMountObject` 保留 inode/revision/state 供 M5 平台 OID 投影。`bucket_access_reads.go` 在挂载持有 metadata 句柄时把常规 list/stat/open 授权路由进去;`readRemoteRange` 在字节传输前检查 metadata/tombstone 视图。
- `go/mount/bucket_cache.go` — `localEntry` 分离本地优先状态与 TTL 约束的 legacy 远端缓存。metadata 基座条目与本地文件/目录、tombstone 按归一化路径合并,防止 `name`/`name/` 同时碰撞。`writeback_restore.go` 在读恢复前为每个持久排队上传恢复本地标记。
- `go/mount/remote_poller.go`、`bucket_access_cloud_files.go`、`cloud_files_refresh_windows.go` — 轮询先重物化 metadata,再把远端-only 基座投影进 Cloud Files。占位符刷新在 pending 写与 tombstone 之外保留本地目录标记。WebDAV、Linux FUSE、WinFsp 经由公共 `bucketAccess` list/stat 方法。轮询细节见 [mount_external_sync](mount_external_sync.md)。

## M5:稳定 OID 投影(已完成)

- `go/mount/metadata/service_core.go` 只暴露平台身份所需的命名空间 ID。`metadata_read.go` 在挂载对象上保留 OID/revision/state,仅当可见条目为 metadata 持有时返回 OID;legacy 本地草稿与系统 overlay 在 M6 前刻意不投影。
- `go/mount/linux_fuse_nodes.go` — lookup/readdir/getattr 稳定属性使用 metadata OID,既有 FNV 路径哈希仅作 legacy 回退。`linux_fuse_oid_test.go` 钉住 rename 稳定 OID。
- `go/mount/winfsp_metadata_windows.go`、`winfsp_fs_windows.go`、`winfsp_fs_helpers_windows.go`、`backend_windows_winfsp_cgo.go` — 目录与打开文件投影保留 OID、发布 `Stat_t.Ino`、启用 cgofuse `use_ino`。
- `go/mount/cloud_files_types_windows.go`、`cloud_files_hydrator_windows.go`、`cloud_files_refresh_windows.go`、`backend_windows_cloud_files_cgo.go` — metadata 条目经投影回调透传。`FileIdentity` = 命名空间+OID,独立远端指纹仍检测内容变化并给过期文件脱水;`cloud_files_identity_windows_test.go` 钉住该区分。

## M6b:挂载写集成(已完成)

- `go/mount/metadata_write.go` — 挂载适配器把 metadata 启用的 `createDirectory`、staged 文件 close、rename、delete 在返回成功前路由进 `metadata.Service`。本地缓存字节保持可读;rename 前移动缓存索引,Desired 事务拒绝时回滚;不经 legacy peer-broadcast 路径宣告本地意图。Cloud Files 完成使用其外部移动变体,只把标记重绑到回调的 `newLocalPath`,因为 Explorer 已移动字节。
- `go/mount/bucket_access_writes.go`、`bucket_cache_rename.go`、`overlay_bridge.go`、`webdav_file.go`、`linux_fuse_file.go`、`linux_fuse_nodes.go`、`winfsp_fs_windows.go`、`cloud_files_watcher_windows.go` — 在同步平台边界传播 staging 错误。`enqueueRenamePath` 为 metadata 会话选择外部移动标记重基;pending metadata 草稿投影持久 OID,legacy 本地-only 草稿仍用回退。
- Known P2(M6b 评审):`winFspBucketFS.Release` 在 metadata `stageLocalWrite` 失败后清除 `open.dirty`,Windows close 失败暂无持久重试记录。与成功 journal admission 分开处理;不要假设本地文件已入队。
- `go/mount/writeback_store.go` — metadata 启用挂载仅把 legacy 队列构造为惰性兼容/控制面:刻意不恢复旧 queue/mutation 记录,新 mutation 不入队。防止两个独立远端写者。无 metadata 命名空间的回退挂载保留旧行为(legacy 队列详情见 [mount_queues_legacy](mount_queues_legacy.md))。

## M6c:页面写集成(已完成)

- `bridge/dispatch_metadata_mutation.go` — profile 域页面→journal 适配器。获取 `DefaultManager`,仅 `ErrNoProfileID` 回退,只在 `Service.WritePath` stage 前打开/stat 文件。`bridge/dispatch_page_mutations.go` — 页面 create/upload/rename/delete 处理器;`dispatch_object_transfer.go` 把 move 送进同一适配器。`copyObject` 与递归 `uploadDirectory` 在存在 `ProfileID` 时显式 fail closed,等待未来的持久 copy/批量操作。
- `go/mount/metadata/service_projection.go` — `PathProjection` 与无 provider I/O 的 `ProjectionCurrent` 检查。`bridge/dispatch_metadata_mutation.go` 在路径锁持有时捕获 mutation 后 inode/revision;`go/mount/external_invalidation.go` 与 `bucket_access_reads.go` 只在该版本仍最新时(under `writebackMu`)应用 `ProjectMetadata*`。晚到的页面 delete/upload/rename 不能隐藏或清除更新的挂载写标记。这些 helper 与 `NotifyExternal*`(legacy 远端确认失效路径)是不同的东西。
- `go/mount/metadata/worker_move.go` — provider 工作前持久化冻结 move 目标,provider 接受后、确认前持久化 `Op.MoveApplied`。重放重新确认冻结目标;pre-persist 崩溃窗口即使对非哨兵 provider 错误也探测,只接受匹配的目标指纹或显式匹配目录标记。`worker_move_test.go` 覆盖链式 rename、本地-only 重放、generic 404 型错误、缺失目录、marker-only 目录。
- Known P2/P3(M6c 评审):页面任务 ID 尚未映射到 worker 传输快照 ID;挂载字节读尚不能服务未确认的页面上传 chunk;Web API/浏览器上传端点在存在 `ProfileID` 时仍 provider-direct;后续桥接输入校验批次应拒绝 `.`/`..` 页面 create/rename 段。WebDAV 404→`os.ErrNotExist` 契约与 worker 对账有单测,但 HTTP 服务器端到端「MOVE applied then retry」fixture 是 P3 测试缺口。不要把以上任何一项当作已完成的持久性行为。

## 页面↔挂载耦合细节(M7)

- Flutter 桌面页面 `list_object_page`、`list_objects`、`head_object` 带 `ProfileID` 时无视挂载状态使用持久命名空间;`ListMountedObjectPage` 与其进程局部快照仅作为显式无身份 legacy 回退存活。页面 create/upload/rename/move/delete 先提交 Desired+journal 并使用 revision 检查的挂载投影,而不是调 `NotifyExternal*`。`NotifyExternal*` 仅保留给 legacy 与 provider-direct Web API 路径;P2P/poll 入口仍需未来的统一对账入口。
- `lib/pages/file_manager_page_restore_sync.dart` / `file_manager_page_actions.dart` / `file_manager_object_browser_sync.dart` — 页面创建的 metadata 目录注册路径/profile/bucket 域任务观察。活动 listing 在该任务、或先前活跃的匹配 metadata 任务到达终态时强制刷新,确认后的远端 mtime 替换本地 pending 快照。挂载对象徽章现包括 mkdir/write/upload/rename/copy/move/delete 任务,并匹配活跃 profile 内的 source/target 路径,防止另一账号的同名桶改变徽章。Widget 覆盖:`file_manager_metadata_task_refresh_test.dart`、`file_manager_object_browser_sync_test.dart`。

## 开发期缓存恢复

命名空间 bbolt 状态在 `~/.cloud-volume/runtime/metadata/v1/<namespace>/metadata.db`;相邻 `namespace.json` 把不透明命名空间 ID 映射到 profile/bucket。Chunk 状态在 DB 持久的 `schema.chunkRoot` 下的 `metadata-chunks/<namespace>`;`CacheDirectory` 仅在命名空间首次创建时决定该 root。需要清掉开发期的过期 metadata 视图时,只在 `Status.PendingOps`、`Status.FailedOps`、`Status.PendingContent` 全为零时重建/搬移两个命名空间 root;否则保留命名空间,不要删除持久意图或受保护 chunk。

## 范围与阶段约束

- **第一阶段 MVP(已锁定):** metadata 重构 + 统一页面/挂载读视图。明确超出范围:journal 驱动远端 worker 之外的跨设备变更 feed、legacy JSONL 迁移、完整回收站统一、冲突 UI。inode/OID 由 metadata store 内部持有;平台可见文件号只需适配侧稳定解析回同一 OID(Linux FUSE 可 `Ino=OID`;WinFsp 可 `FileIndex=OID` 或 lookup;Cloud Files 占位身份可编码 OID 或由适配器解析;macOS WebDAV 外部 inode 仍由 webdavfs 持有)。验收是页面/挂载视图一致,不是跨平台 inode 号相等。推荐实施批次 M1–M7 见计划文档。
- **统一元数据架构顺序(binding):** metadata store → 统一读视图 → 公共写入口 → journal 驱动远端 worker → 跨设备远端变更 feed。本开发阶段本地 metadata 是可重建缓存:不迁移旧 writeback/mutation JSONL、无 legacy 队列 feature flag、schema 不匹配/损坏即删除并从远端 listing 重建。Pending、尚未远端同步的内容是唯一数据级状态,必须受 reset guard 保护。
- **跨设备远端新鲜度:** 当前 P2P 只在远端确认变更后发送可选父目录刷新提示,默认关闭且不持久。回退 poller 只扫最近打开目录(上限 12);SFTP 经 `SupportsMountRemotePolling() == false` 显式禁用。因此第二台挂载不能可靠观察第一台设备上的 rsync 覆写。规划中的 inode B+Tree 只用每设备本地 OID;跨设备同步必须使用持久的远端不可变事件 feed(按规范远端路径 + 远端指纹 + origin 序列键),经 HEAD/list 验证后失效/脱水旧本地内容。细节与能力回退见 [MountMetadataJournalPlan.md](../MountMetadataJournalPlan.md) 与 [file_sync_p2p](file_sync_p2p.md)。
