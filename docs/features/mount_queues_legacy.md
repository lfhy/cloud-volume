# Legacy Mount Queues — 回退专用写回队列体系

M6b 之后(见 [mount_metadata_core](mount_metadata_core.md)),metadata 启用的挂载只把这套队列作为惰性兼容/控制面(`writeback_store.go` 刻意不恢复旧记录、新 mutation 不入队)。无 `ProfileID` 的回退挂载仍使用以下完整行为。挂载写是异步的,由 `go/mount` 内四个协作队列承担:文件上传、目录标记创建、重命名、删除各有不同的持久性与顺序保证。

## 关键文件

- `go/mount/bucket_access.go` — `bucketAccess` 持有全部队列。`newBucketAccess` 创建 `dirSync`(`newDirSyncQueue`)、`writeback`(`newWritebackQueue`)、`deletes`。`writebackMu` 排序每个本地路径 mutation(文件 staging、mkdir、删除、外部失效、重命名);`mutationMu` 在本地顺序固定后串行化对应 provider move/delete。`close()` 关停队列;`drainWritebackContext` 在调用方超时时排空文件写回而不丢弃持久条目。`release()` 只关停 `dirSync`。
- `go/mount/writeback_queue.go` / `writeback_queue_drain.go` — 文件上传队列。`stageLocalWrite`(WebDAV close、FUSE/WinFsp publish、Windows watcher 进入)保存本地标记并在 `writebackMu` 下调 `enqueue`;队列延迟 `WritebackQuietSeconds` 后经可取消分发器排空。取消命中队列背压时,每个未发送条目重新武装为常规分发而不是滞留 `queued=true`;`drainPath` 只在其同步远端 move 前强制 rename 源/子树落定。`flushNow` stat 已解析本地路径、size/mtime 变化时刷新、`UploadFile`、HEAD 验证、缓存更新、peer 广播、store 删除。源缺失 = 成功清理(`flush-missing`),缓存文件消失的上传被静默丢弃。
- `go/mount/writeback_store.go` — 每 PID JSON store + 按 store 目录的全局注册表。每条写回记录有 hash scope:profile/视图身份 + provider 特定主体(S3 access key、WebDAV 用户名、FTP/SFTP 用户名+端口或匿名+端口、百度 refresh token)。Store 合并 key 是 `scope + path`,不同远端的相同虚拟路径在压缩中各自存活。活跃 in-process 队列拒绝附加变更后的 scope。
- `go/mount/writeback_restore.go` — `restorePersistedEntries` 只恢复本地源是 `sessionRoot` 或 `cacheRoot` 内常规文件的匹配 scope 记录;不匹配或 legacy 无 scope 记录在压缩后的 store 中保持休眠,不被重放或删除。`restorePersistedMutations` 应用同一 scope 检查同时保留不匹配项、重建屏障/重基,并**不带 `run` 闭包**重放匹配的 rename 记录。
- `go/mount/dir_sync_queue.go` — 目录标记创建队列仍是内存态。`stageLocalDirectory` → `queueRemoteDirectory` → `enqueue`;2 个 worker 调 `CreateDirectory`。最新 provider/pool 失败捕获为进程局部 `[dir-sync]` 错误,该路径成功创建后清除,且仍关闭 entry fence 使其不阻塞后续写回。`rebaseAndFence` 同时用于排队的 Cloud Files rename 与同步 `renamePath` 调用。
- `go/mount/bucket_access_writes.go` / `bucket_cache_rename.go` — `createDirectory` 只本地 staging + 入队标记。`stageLocalWrite` 保护标记→队列交接。同步 `renamePath`(macOS WebDAV、Linux FUSE、WinFsp)持有公共路径 gate、重基/fence 目录标记、排空匹配的排队/运行中上传、等待/重基 in-flight 删除意图,然后移动远端源;缓存字节移动预检且仅在成功后建索引,多文件失败尽力回滚。`enqueueRenamePath`(仅 Windows Cloud Files)捕获带屏障 generation 的 scoped 持久 `mutationRecord` 与旧路径远端缺失时远端创建重命名目录的 legacy `run` 闭包。
- `go/mount/writeback_rename_queue.go` — 重命名/mutation 分发器。`enqueueMutation` 持久化记录、创建屏障 + 源重基、排队操作。`executeQueuedRename` 排空 generation ≤ 屏障的上传、等待 dir 屏障、运行闭包一次,然后状态驱动的 reconciler 重试。未完成屏障经 `generationBlockedLocked`(50ms 重武装轮询)阻塞**更晚 generation 的上传**。
- `go/mount/mutation_reconcile.go` — `reconcileRemoteMove` 状态表:缺失/存在 → 完成;存在/缺失 → Move;两者都在 → Copy+硬删除;**缺失/缺失 → `errMutationStateConflict`,永远重试**——它绝不创建目的地或上传本地内容。`applyMutationSuccess` 修正缓存/广播。
- `go/mount/delete_queue.go` — 独立删除队列,带重试。跟踪 claimed/running 条目,使 rename 只在目的地远端后置条件成功后重基 pending 与未开始 的远端删除目标。provider 删除在持有 `mutationMu` 时快照其路径,防止过期或撕裂路径超越 move。
- `go/mount/types.go` + `lib/widgets/file_manager_bucket_browser_actions.dart` — 挂载状态合并 session、rename-mutation、dir-sync 错误。桶操作行显示非交互警示图标,tooltip 含完整错误,挂载保持活跃。
- `go/mount/webdav_fs.go` / `webdav_file.go` — Finder 路径:MKCOL → `createDirectory`(本地 + dirSync),MOVE → `webDAVFS.Rename` → `renamePath`;PUT close → staged temp 重命名进哈希缓存路径 → `stageLocalWrite`。目录 FileInfo mtime 来自 provider/metadata 对象,目录 listing 缺 mtime 时固定 epoch 回退,反复 PROPFIND 不会让 Finder 报告变化的文件夹时间戳。嵌套 MKCOL 依赖 metadata 的本地-only Desired-directory 短路直到远端标记确认。
- `go/mount/macos_mount_stop.go` — macOS `mountSession.stop` 在探测/卸载 WebDAV 卷前排空写回。用 `transferTimeout` 作为有界 context;排空失败或超时保持挂载服务器与队列存活、清除 `stopping`、记录可操作 `LastError`,让用户重试而不是静默丢弃 pending 工作。
- `go/mount/manager.go` — 会话替换、全局清理、状态探测在后端拒绝 Stop 时保留会话并保持 `mounted=true`、清除 `stopping`;防止另一配置附着到仍存活的持久队列。`startMountSession` 在 `CleanupStale` 或部分 `Start` 失败时关闭 access/metadata 队列——除非部分启动留下活跃挂载且清理 Stop 失败:该会话带错误注册以保持可重试。成功 Stop 正常移除会话。

## 数据流(Finder:建目录 → 重命名 → 上传文件)

1. MKCOL 默认名 → 缓存本地目录条目 + `dirSync.enqueue("未命名文件夹")` 标记创建。
2. MOVE → `renamePath`:进入公共路径 gate,重基/fence 排队标记创建,排空匹配写,然后在远端 mutation 互斥下移动远端源。只有远端目的地确认后,pending/未开始的删除目标才被重基。源缺失的本地-only 目录验证重基后的目的地标记并完成,不发无效 move。Windows Cloud Files 用 `enqueueRenamePath`,额外持久化 move。
3. PUT close → 哈希缓存文件 + `stageLocalWrite("正确名/文件")`,原子发布本地标记与 `writeback.enqueue` 记录(显示为 `mount-writeback-*` pending 任务,`sync_wait` → `upload_wait`)。
4. 上传在静默期与任何 rename 屏障后执行;各后端父目录行为不同(SFTP/FTP 自动建父;WebDAV `put` 不 MKCOL 父;S3 key 是平的)。

## Gotchas / 已知风险

- **目录创建完全不持久**;失败呈现为进程局部挂载错误,但崩溃/重挂后无重试状态存活。重基修复防止 legacy 同步重命名创建旧标记名,但标记完成前崩溃仍丢失该内存态创建。
- **Scope 不匹配刻意休眠:** 变更账号/root-prefix 的记录本地保留但绝不自动上传到新远端。无 scope 的 legacy 记录同样不迁移;恢复需要回到原 profile 或手动处理缓存内容。
- **Known P2(rename 取消):** `renamePath` 等待前,`rebaseAndFence` 已变更排队标记。等待被取消时标记重基不回滚,重试可观察到已变更标记而缓存仍显示源路径。
- **Known P2(legacy 写回 store 持久化):** 队列 JSON 仍用直接 `os.WriteFile` 写,无临时文件重命名或父目录 fsync;断电可使整个队列不可读。恢复超过 64 个缓冲 rename mutation 也会在分发器启动前阻塞。需要专门的持久化加固批次,而不是在此局部语义修改。
- **Known P2(外部挂载消失):** `syncSessionLocked` 调用的成功 Stop 尚未在状态码移除会话前停止远端 poller。外部卸载检测因此可能留下短暂指向已释放 access 状态的 poller。
- **卡住的 rename 阻塞桶:** 未完成屏障(如 absent/absent 远端状态、无 `run` 闭包的恢复记录)使 `generationBlockedLocked` 无限期推迟后续上传,reconciler 以 `mutation state conflict` 永远重试。
- **`renamePath` 本地-only 捷径**不经远端创建重命名目录即返回成功;正确性依赖后续标记创建/上传(依后端而异)。
- 桥接日志:`~/.cloud-volume/runtime/logs/bridge.log`(`[mount/writeback]`、`[mount/dir-sync]`、`[webdav/mkdir]` 行);每桶队列:`~/.cloud-volume/runtime/mounts/<bucket>/{writeback,mutations}`。
