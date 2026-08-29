# macOS WebDAV Mount — 本地优先写与挂载生命周期

macOS 经 `webdavfs_agent` 挂载回环 WebDAV 服务器。文件内容先落本地 staging/缓存文件,再进入共享延迟写回队列;面向 Finder 的 `PUT` 绝不等待上游 provider 上传。历史评审结论见 [PROJECT_GUIDE](../PROJECT_GUIDE.md) 2026-07-30 macOS WebDAV 审计记录。

## 写路径:关键文件与数据流

- `go/mount/webdav_http_handler.go` / `webdav_fs.go` — 回环 `x/net/webdav.Handler` 把文件打开委托给 `webDAVFS`。内容写标志选择 `newWritableWebDAVFile`;读选择支持范围的读句柄。精确 `os.O_RDWR` 打开是 `PROPPATCH` 用的 `x/net/webdav` 元数据探测,路由到 metadata-only 句柄。
- `go/mount/webdav_metadata_file.go` / `webdav_metadata_file_test.go` — metadata-only 句柄支持 `Stat` 而不 staging/调度对象内容,刻意不实现 `webdav.DeadPropsHolder`,保留此前的禁止属性响应。测试断言元数据打开不入队写回,截断式 `PUT` 打开保持本地优先。
- `go/mount/webdav_file.go` — 可写句柄在请求体到达期间使用 `<runtime>/mounts/<bucket>/staging/<hashed-key>`。`Close` 把该文件移入 `<cache>/mounts/<bucket>/<hashed-key>`,调 `registerLocalWrite`,再 `scheduleUpload`。
- `go/mount/webdav_logging.go` / `webdav_request_context.go` / `webdav_fs.go` / `webdav_lock_null.go` — x/net/webdav 的缺失资源 `LOCK` 路径用与 `PUT` 相同的 `O_RDWR|O_CREATE|O_TRUNC` 标志;日志包装器经请求上下文携带 HTTP 方法,缺失 `LOCK` 返回内存 lock-null 文件而不是 staging 零字节元数据写。后续 `PUT` 仍走常规可写路径(含空 payload)。`webdav_lock_null_test.go` 钉住两例。
- `go/mount/webdav_finder_temp.go` / `local_overlay.go` / `overlay_bridge.go` / `webdav_finder_temp_test.go` — Finder 每文件 `.BC.T_*` 拷贝 staging 文件是本地 overlay 路径。其 `PUT` 绝不进 Desired 树;最终跨界 `MOVE` 把字节拷进常规缓存路径并产生一个最终名 metadata 写。AppleDouble `._.BC.T_*` → `._*` 移动保持全本地 overlay 元数据。刻意与常规 dot-file 处理分离,用户可见 dot 文件仍正常同步。
- `go/mount/bucket_access_writes.go` / `writeback_queue.go` / `writeback_store.go` — `scheduleUpload` 持久化 pending 记录、发布 `sync_wait`、重置该文件配置的静默 timer(默认 10 秒),然后后台 worker 池上传。Finder 继续写后续文件时更早文件可以已在上传;这是有意的异步行为,不是前台依赖。远端上传成功清除本地 overlay 标记与持久记录;缓存文件本身保留供读。
- `go/storage/tracked_upload.go` / `ftp_backend_io.go` / `sftp_backend_io.go` / `webdav_backend_upload.go` — FTP、SFTP、WebDAV provider 上传共享一个上下文感知 reader:启动排队传输、推进已拷贝字节、尊重取消、完成成功/失败。S3 在 `go/s3/upload_resume.go` / `http_stream.go`、百度在 `go/storage/baidu_pan_backend_io.go` 同样自持任务 ID 的 start/advance/finish 生命周期。`ftp_backend_test.go`、`sftp_backend_test.go`、`webdav_upload_tracking_test.go` 断言挂载式 `UploadFile` 成功调用结束在 `14/14` 而不是停在 `sync_wait`。SFTP 每操作仍建立新 SSH/SFTP 连接,写回执行单独 `HeadObject`,握手延迟与服务器连接限制继续影响多小文件吞吐,但不改变本地优先前台语义。
- `go/storage/sftp_backend.go` 同时实现 `MountPrefetchPolicy=false` 与 `MountRemotePollingPolicy=false`;`go/storage/scoped_backend.go` 经 RootPrefix 包装转发两个策略。Finder 根 listing 因此不启动最多 8 个子目录的投机读,Finder/Spotlight 递归 `PROPFIND` 路径不会变成每 5 秒最多 12 个新 SSH/SFTP 连接的重复 P0 轮询流。显式目录导航保持按需。TCP 拨号用 `DialContext`,SSH 握手继承请求期限,取消关闭 socket,读不会在连接/握手期间静默超出挂载请求超时。
- `go/s3/transfer_monitor.go` / `lib/state/transfer_task.dart` — 挂载写回先注册 `pending` 任务 `sync_wait`。每个现行 provider 上传实现消费任务 ID 并推进/终结共享监控,成功写回立即离开 `sync_wait`,不等监控 10 分钟修剪窗口。
- `go/mount/webdav_logging.go` — 成功的 `PUT`、`COPY`、`PROPPATCH` 当前不记录日志;常规日志无法计时前台写路径。`writeback` enqueue/ready/flush 行与 staging/cache/writeback 目录是可靠的现行证据。

## Finder PROPPATCH 处理(binding)

Finder 对创建日期等 dead property 发送 `PROPPATCH`。`golang.org/x/net/webdav` 在检查句柄是否实现 `DeadPropsHolder` 前以精确 `os.O_RDWR` 打开目标。`webDAVFS.OpenFile` 必须保持该精确标志路由到 `metadataWebDAVFile`;送进 `newWritableWebDAVFile` 会冷启动下载目标并在无 `Write` 发生时于 `Close` 调度冗余写回。常规 `PUT` 打开含 `O_CREATE`/`O_TRUNC` 内容写标志,仍走 staging、缓存注册、延迟写回。

metadata 句柄刻意不实现 `DeadPropsHolder`,不支持的 Finder 属性保留禁止响应而不触对象内容。**不要**把精确 `O_RDWR` 合并回通用可写分支;仅缩短 `writeback_quiet_seconds` 不能阻止冗余传输,提高写回并发会恶化 SFTP 握手重置。

诊断卡在 `sync_wait` 的 SFTP 行时,同时检查 `<runtime>/mounts/<bucket>/writeback/queue-*.json` 与远端对象。空持久 map 表示写回层没有可恢复 pending 工作。接受任务 ID 的 provider 上传实现必须显式 start/advance/finish 共享传输任务;更快修剪过期快照只会掩盖生命周期 bug。

## 配额投影

- `go/mount/webdav_quota.go` / `webdav_quota_test.go` / `bucket_access.go` / `go/storage/quota_cache.go` — 根读句柄经 `webdav.DeadPropsHolder` 暴露 RFC 4331 `quota-available-bytes` 与 `quota-used-bytes`,精确 `O_RDWR` 元数据句柄仍省略该接口。`newBucketAccess` 从 `storage.CachedBucketQuotaForMount` 播种首个响应;同账号/桶的新鲜与过期条目都可用,过期条目立即后台刷新。优先 `BucketSettings.CustomQuotaBytes`,保留 provider used 字节、used 钳到 total、瞬态刷新失败时保留最后已知容量。macOS 挂载启动没有同步配额请求。真正缓存未命中保持非阻塞并启动既有 30 秒会话内后台刷新。测试覆盖新鲜/过期缓存读、播种首请求配额、失败/成功后台刷新、非阻塞未知配额、自定义 total 优先。
- macOS 15 上,仪表化挂载可在 <1ms 内从回环 Depth-0 `PROPFIND` 返回正确配额 XML,而首个 `statfs`/`df` 仍阻塞或报 `0/0` 约 90 秒;紧接着的第二次查询报告正确容量。这是 Apple `webdavfs_agent` 内部的延迟状态发布,不是同步上游配额/list 调用。等待 `statfs`、预刷新 root、禁用 HTTP keep-alive、移除 AppleScript `POSIX path` 强转、保留 `osascript` 运行都未改变且已回退。**不要**把任何此类等待放回挂载完成路径。
- 本地 macOS 验证时,不要对同一 SFTP 账号并发运行 `/Applications/云卷.app` 与 `make run` 调试构建。旧进程保有自己的挂载/poller 会话,大致倍增连接压力(2026-07-30 复现中,终止安装版把 SFTP 根 listing 从约 90 秒降到 0.45–0.75 秒;调试构建 0.4–0.7 秒挂载,Finder `open` 约 0.2 秒完成,无深层 `[mount/poll]` 刷新)。

## 读路径缓存

- `go/mount/bucket_access_reads.go` / `bucket_cache.go` / `bucket_access_stat_cache_test.go` — `statPath` 把新鲜完整目录 listing 对命中与未命中都视为权威,把挂载创建本地目录的缺失子项视为本地缺失。Finder 在 `PUT` 前探测每个目的地;这些负缓存路径防止多小文件拷贝对每文件做一次同步 SFTP `HeadObject`/连接握手。过期或未知目录仍落回 provider,远端覆盖保持可发现。`ensureLocalFile` 额外从 staged chunk 服务 metadata pending 文件:验证 inode+generation 缓存戳、在路径 keyed singleflight 下把 chunk 物化进常规缓存文件,保持进行中的挂载本地写标记比更新的页面 generation 权威。`readRemoteRange` 在任何 provider 调用前从 `ReadPendingRange` 应答 pending 范围。

## 挂载生命周期

- `go/mount/macos_mount.go` / `macos_mount_stop.go` / `macos_mount_test.go` / `macos_mount_integration_test.go` / `macos_command.go` / `macos_command_test.go` / `system_mounts.go` — 默认挂载调用非交互 `mount_webdav -S -v <mountName>`,然后等待精确随机回环 URL + 挂载路径出现在 `mount -t webdav` 中,上限 30 秒。命令成功本身不等于注册完成,但命令错误或超时绝不从表行恢复成成功挂载。`/var` 与 `/private/var` 别名经解析父路径比较,不触碰挂载根。失败尝试清理最多 45 秒;`mountAttempted` 保持 server/access 所有权可重试(系统卸载失败时),活跃状态探测保持 URL 限定直到该尝试确认,外来同路径卷不被收养。Finder `open` 是异步的且由每路径 single-flight gate 保护,因为阻塞在 WebDAV 文件系统调用的进程可能比 5 秒更久忽略 `CommandContext` 取消。opt-in 真实生命周期测试用 `CLOUD_VOLUME_RUN_MACOS_MOUNT_INTEGRATION=1` 跑;常规测试 mock 外部命令。
- `go/mount/macos_mount.go` `runMacOSFinderOpen` — `openMountPath` 不再用 `runLoggedCommand`/`CombinedOutput`。macOS LaunchServices(`open` 启动)继承 stdout/stderr 管道,Finder 在新挂载 WebDAV 卷首次 `statfs` 期间持有它们约 90 秒;`CommandContext` + `WaitDelay` 不能可靠回收,因为后代经 XPC 而非 fork 启动。实现 detach 进程(Stdout/Stderr → `os.DevNull`,`Setpgid: true`)、`Start()` + 有界 `Wait()` goroutine(3 秒上限),`open` 仍在运行时记 "dispatched"。每路径 single-flight gate(`mountOpenGate`)仍防重复打开。**绝不**把 `CombinedOutput` 放回挂载 WebDAV 路径的 `open`。测试必须替换包级 `launchFinder` hook,而不是给真实 `openMountPath` 传 `t.TempDir()`——否则跑 `go test ./go/mount` 会在 macOS 测试临时目录真正打开 Finder。
- `go/mount/macos_mount_stop.go` — 停止顺序与失败语义见 [mount_queues_legacy](mount_queues_legacy.md) 关键文件节。
- macOS `webdavfs_agent` 可独立崩溃并移除卷(PAC 失败由 OS 报告,而非 Go WebDAV handler 生成),因此 [opt-in 集成测试](../../go/mount/macos_mount_integration_test.go) 真实执行递归 `ditto` 拷贝并验证挂载仍活跃。`go/mount/webdav_server.go` 记录非探测 handler 错误而不重复普通 Finder 404 探测。

## 挂载成功探测必须匹配源 URL,而不是路径名(binding)

- `go/mount/system_mounts.go` 经 `parseMountEntry` 解析 macOS `mount -t webdav` 行,把**源 URL**(`http://127.0.0.1:<random-port>/<scope>/`)与磁盘路径都保留进 `mountEntry`。`parseMountPoint`/`parseMountPaths` 仍是无 URL 需求的卸载/清理调用方的路径-only 薄包装。
- `go/mount/macos_mount.go` `findMountedWebDAVPath`/`probeMountedWebDAVPath`/`waitForMountedWebDAVPath` 要求行的源 URL 在 `normalizeServerURL`(小写 scheme/host、路径尾斜杠)后等于 `serverURL`。同名但不同端口的行——过期卷、另一进程挂载、requested-path 分支 `MkdirAll` 创建的目录——被拒绝。`canonicalMountPath` 只解析父目录,使 `/var/...` 与 macOS 报告的 `/private/var/...` 匹配,而不对活跃 WebDAV 根调用潜在阻塞操作。
- **不要**放宽回路径名-only 匹配。曾经的「尽快结束启动」优化轮询挂载表并在任意路径匹配时立即返回;由于 `parseMountPoint` 丢弃源 URL,残留同名 `/Volumes/云卷-<bucket>`(或 `MkdirAll` 创建的请求目录本身)满足探测、活跃 `mount_webdav` 被取消、UI 报「已挂载」而 Finder 什么都没有;点击 open 随后对从未成为真实 WebDAV 卷的路径无限阻塞。SFTP 因高首次访问延迟与禁用的预取/轮询最先暴露。
- 回归锚点在 `go/mount/macos_mount_test.go`(`TestFindMountedWebDAVPathRejectsSameNameDifferentPort`、`TestFindMountedWebDAVPathRejectsPathMatchWithoutURL`)与 `go/mount/system_mounts_test.go`(`TestParseMountEntryExtractsSourceURLAndPath`)。保持绿色。
- 自动 WebDAV 预热已移除:`os.Stat`/`os.ReadDir` 无上下文取消,卡死的 `webdavfs_agent` syscall 会使挂载在超时后仍忙。Finder 首次访问执行常规初始化,挂载/卸载生命周期避免产生无法回收的文件系统 syscall。

## 挂载必须用同步 mount_webdav,绝不用 osascript(binding)

- `go/mount/macos_mount.go` `mountWebDAV` 总是通过同步 `/sbin/mount_webdav` 命令在显式解析路径挂载。`session.start()` 传 `s.mountPath`(已由 `macOSWebDAVBackend.Initialize` 解析为调用方路径或默认 `/Volumes/云卷-<bucket>`),不是原始 `s.requestedPath`。
- `osascript "mount volume"` 分支与 `appleScriptStringLiteral` 已**完全移除**。`osascript "mount volume"` 是 fire-and-forget:在内核注册卷并立即返回,而 `webdavfs_agent` 异步完成约 90 秒握手。旧代码会从过期挂载表条目返回「已挂载」,取消仍在运行的 osascript 可能打断握手——Finder 看不到/打不开卷,`os.Stat` 阻塞 30 秒以上。
- `/sbin/mount_webdav -S` 无隐藏认证/无响应服务器 UI 运行。其成功进程退出表示挂载请求被接受,不必然系统已发布卷;启动因此在成功后等待精确 URL/路径行。反之,进程错误或超时 fail closed,只能触发清理,绝不从挂载表行恢复成功。不要重新引入早退/取消行为,或用 `statfs`/`os.Stat`/`os.ReadDir` 作为完成探测:Apple 首次 VFS 访问可独立于注册而阻塞。
- **默认路径权限:** `/Volumes` 在常规 macOS 安装是 root 属主。`prepareMacOSMountPath` 只对不可写的默认托管路径 `/Volumes/云卷-<bucket>` 回退,创建 `~/云卷/云卷-<bucket>` 并在挂载状态返回真实路径。显式自定义路径仍失败而不是被静默搬迁。过期挂载清理扫描两个托管根。
- **不要**重新引入 `osascript`/`mount volume` 路径或把空 `requestedPath` 路由到 fire-and-forget 挂载。调用方需要自定义挂载点时,必须在 `mountWebDAV` 前解析为具体路径。回归锚点:`go/mount/macos_mount_test.go` 的 `TestMountWebDAVRejectsEmptyMountPath`。

## 孤儿挂载启动清扫(macOS)

- `go/mount/orphan_mount_sweep_darwin.go` / `orphan_mount_sweep_other.go` — `SweepOrphanMounts()` 枚举 `mount -t webdav`,只保留源 URL 是无活跃 TCP 监听的 loopback `127.0.0.1:<port>` 的托管 `云卷-` 路径(`/Volumes` 或 `~/云卷` 下),强制卸载其余。退出时清理(`AppDelegate.applicationWillTerminate` dlopen 路径与 Dart `AppExitCleanup`)是尽力的;该清扫保证崩溃、强退、挂死进程后的自愈。`orphan_mount_sweep_test.go` 钉住 loopback/死端口/活监听/非托管规则。
- `bridge/dispatch_mount.go` 暴露 `sweep_orphan_mounts`(非 macOS 为 no-op);清扫在后台 goroutine 运行,顽固忙碌卷不会串行化其它桥接调用,完成/错误落入桥接日志。`lib/pages/app_bootstrap_page.dart` 每次应用运行恰好触发一次(一次性 guard 跳过软刷新,并发启动的挂载不会被误判为孤儿)。`RemoteStorageGateway.sweepOrphanMounts()` 桌面实现为桥接调用,Web 为 0。
