# Changelog

## Unreleased

- 新增 macOS 孤儿挂载启动清扫：App 崩溃、强退或进程挂死后残留的 `webdavfs_agent` 挂载会在下次启动时被自动卸载。清扫只针对托管前缀（`/Volumes/云卷-*`、`~/云卷/云卷-*`）且指向本机回环端口、端口已无监听的挂载，正常挂载和其他应用的 WebDAV 卷不受影响；非 macOS 平台为空操作。

- 修复 macOS Finder 大量小文件复制的本地入口放大：WebDAV `LOCK` 的缺失资源探测不再写入零字节 metadata journal，Finder 的 `.BC.T_*` 临时文件保持在本地 overlay，只有最终 `MOVE` 才生成一个最终文件名的写回任务；正常（包括零字节）`PUT` 仍照常落入本地 Desired 树。挂载/page 写入的 inode、内容引用、块 nlink 与 journal 改为单个 bbolt 事务提交，远端上传仍保持异步。
- 修复 macOS Finder 递归复制的兼容性与可诊断性：深层目录创建会在本地 Desired 树中补齐父目录，避免旧版路径上的 `409 Conflict` 被 Finder 误报为“名称太长或包含无效字符”；祖先目录在复制中重命名时，未同步子目录继续按已确认的远端父路径建立，再执行目录移动，避免任务队列永久互等。系统 WebDAV 卷意外消失时会明确显示断开原因，状态探测瞬态失败不再主动拆掉会话或遗失部分启动会话；状态未确认的部分启动会话也不会被误报成挂载成功。新增真实 `mount_webdav + ditto` 递归复制的 opt-in Go 集成测试。另修复上游 WebDAV 列表把合法文件名中的 `+` 误解为空格的问题。
- 修复 SFTP、FTP 和 WebDAV 的远端修改时间在非 UTC 客户端发生二次时区偏移：所有 provider 统一输出客户端本地时间，macOS WebDAV / Linux FUSE 与 Windows WinFsp 也按本地时区还原该无时区时间，不再把它误作 UTC。
- 修复 metadata worker 的退出 drain 与后台轮询并发时可能让“覆盖式重命名”的 source move 先于旧目标 delete 执行，进而删掉刚移动的新对象：完整 claim/执行 pass 现已串行，且 drain 在后台 provider 调用活跃时仍可响应取消。
- 优化 metadata 分块暂存的本地持久化路径：保留块文件和最终 hash 目录的同步、缓存保护与启动 GC，但移除可恢复 tmp 源目录和重复 manifest 的同步步骤，降低 Finder 复制 Git 等大量小文件时的本地写入开销。
- 修复 Finder 递归拷贝期间 metadata worker 按单个操作的 quiet 计时提前向 SFTP/WebDAV 推送：同一 namespace 的本地 mkdir/write/rename/delete 现在共享静默屏障，任务队列展示实际等待截止时间；重启会恢复未完成操作的剩余静默期，人工立即执行只跳过一次，卸载 drain 仍会收尾。取消测试同时区分“远端明确不存在”与“结果待对账”两种状态。
- 修复 SFTP 页面新建目录在远端已确认后仍显示空的最后修改时间和“已同步”状态：metadata 确认会持久化 SFTP `Stat` 时间，目录任务会正确显示等待/同步状态，并在完成后自动刷新当前目录。
- 修复连续写入的时间回滚：较早远端确认不会覆盖较新待同步写入的本地时间；若后者取消，页面会恢复已确认的远端最后修改时间。
- 修复 macOS Finder 复制多层目录时误报“名称太长或包含无效字符”：未同步的本地父目录不再被强制向 SFTP 远端列举，递归 `MKCOL` 和后台刷新都会按 Desired 树处理。
- 统一任务队列修复：metadata journal 接管的页面上传、移动、重命名和删除不再与 Dart 兼容执行任务重复展示；上传/删除进度弹窗仍保留临时执行快照。应用更新进入不可逆安装阶段后会隐藏取消并拒绝无效取消请求。
- 兼容队列升级：metadata 页面操作的临时执行快照不再伪装成可取消任务；旧版 `transfer_queue.tasks.v1` 会在升级时失效，避免重启后再次显示无法归属的重复页面操作。

- Unified physical task projection now preserves profile ownership across legacy mount/non-S3 uploads, downloads, copies, moves, and deletes; it reports operation-specific phases, local destinations, current-file and multipart ranges, and excludes resumed bytes from throughput estimates. Page renames now use the tracked move path. App-update tasks now show their asset name and become non-cancelable once installation starts.
- Fixed mounted-file read history showing `bytes=...` as the task path. It now shows the remote file path with the exact requested byte range as supporting detail across desktop and Web task projections, including profile-scoped Web task requests.
- Fixed macOS WebDAV mounts reporting success after a 20-second `mount_webdav` timeout while Finder still had no usable volume. Mount startup now uses non-interactive `-S`, retains the bucket display name, waits for the exact loopback URL/path mount-table registration, normalizes the `/var` and `/private/var` aliases, and fails closed with retryable cleanup when registration or unmount fails. Retained failed attempts keep using that exact ownership probe, so a foreign WebDAV volume at the same path cannot be promoted or unmounted. Added an opt-in real macOS Go mount test plus nonblocking open-dispatch coverage.
- Fixed a mount/task-queue false-stall: Finder directory mtimes now remain stable when providers omit directory timestamps, the task store purges legacy metadata physical rows, and remote verification has a bounded deadline. Post-upload verification failures now reconcile without replaying an overwrite against its old fingerprint. SFTP HEAD now preserves connection/permission errors instead of misreporting every failure as a missing object.
- Added the unified remote-task queue: durable journal operations are projected as effective `RemoteTask` entries (stable `sync:<namespace>:<group>` IDs, folded mkdir/rename/write chains, dependency reasons, physical transfer phases) across desktop and Web with the same paged JSON protocol. Pending cancellation rolls back Desired state and chunk links atomically; running cancellation exposes `cancel_requested`/`reconciling` until the provider outcome is reconciled. Task history is scoped per profile/bucket and compacted after 30 days.
- The transfers page, sidebar status, and file-sync cards now render only the unified `RemoteTaskStore` view with cancel/retry/trigger and expandable raw-operation detail. Runtime transfer snapshots remain execution phases instead of a second task list, and sync tasks carry their profile identity without ID-string parsing.
- Hardened the unified queue projection: journal sequences remain monotonic after history cleanup, mixed lifecycle segments get distinct control IDs, raw events preserve their actual kind/state/path, and verifying or canceled operations recover through durable provider reconciliation. Dart-only preview, batch, mount-badge, and app-update progress now use the local `RemoteTask` adapter instead of rendering `TransferQueue` rows.
- Task history cleanup is now explicit and selective: selecting finished tasks offers "清理历史 <n>" and removes exactly those terminal entries (Go keeps any entry still protecting a later dependency); the page-level "清理历史" button removes all compactable terminal history instead of being limited to 30-day-old rows. Metadata worker physical snapshots are no longer mirrored as duplicate cancelable local rows; their progress stays embedded in the durable task.
- Fixed default macOS mounting failing with `mkdir /Volumes/云卷-<bucket>: permission denied`: the managed default path now falls back to a user-writable `~/云卷/<云卷-桶名>` location (custom paths still error when not writable), and stale-mount cleanup scans both managed roots.
- Fixed macOS WebDAV mounts disappearing after startup confirmation: mount startup no longer cancels `/sbin/mount_webdav` when the mount table row first appears, and no longer launches an uncancellable filesystem prewarm syscall that could make Finder and later unmounts hang with `Resource busy`.
- Added the first-stage persistent inode metadata core (`go/mount/metadata`) with bbolt-backed inode/dirent B+Trees, durable operation journal, namespace registry, reset guard, and remote worker scaffolding. This is the foundation for the unified file-manager/mount metadata view; legacy mount queues continue to serve reads/writes until the migration batches land.
- Added immutable profile identities (`profileId`) so metadata namespaces remain stable across account display-name changes.
- Metadata worker now purges the full descendant subtree (inode records, dirent tables, staged content) after a confirmed directory delete, orders dependent writes/mkdirs behind unfinished parent ops, drains namespaces in parallel at app exit, lazily backfills legacy profiles with stable `profileId` identities on first load, and resolves delete targets through the desired path for never-synced children.
- Page listings (`list_object_page`) now consult the persistent metadata namespace before mount-session caches or provider-direct listing (M2): buckets with a `profileId` are served by the durable inode view with stale-cursor reload semantics; configs without an identity fall back to the previous path. Added a `metadata_namespace_status` bridge diagnostic.
- Pending metadata content now uses fixed 4 MiB SHA-256 content-addressed chunks with per-chunk reference counts. Chunks are deduplicated under the configured cache root, safely reconstructed for uploads, protected from cache cleanup while pending, and swept when orphaned after a restart.
- Fixed metadata chunk staging so cache cleanup cannot evict an earlier block before a multi-chunk write commits; ordered same-inode write/rename operations; made the reset guard account for in-flight journal operations; and prevented exit draining from completing while an operation is still running.
- Fixed metadata page reads to retain profile identity across Flutter/bridge JSON, share a process-wide namespace manager, and honor account `RootPrefix` scopes.
- Fixed legacy mount write durability: remount now restores queued files from the configured cache root, macOS drains writeback before unmount with a retryable timeout, directory-marker creates follow synchronous rename paths, and external uploads no longer delete a still-pending local write.
- Hardened legacy mount durability further: canceled drains leave every unsent entry runnable; persisted writes and rename mutations are bound to account/endpoint/root-prefix scope and mismatched records remain dormant; local staging and queueing are atomic against external invalidation; renamed pending files move with their queue entries; retryable stop failures retain their live session. Directory-marker failures now surface beside the bucket mount action and clear after a successful retry.
- Fixed follow-up mount durability gaps: writeback scope now uses provider-specific stable principals (including FTP/SFTP port and Baidu refresh token), synchronous rename waits for matching running uploads before moving remote objects, and a failed local cache rename leaves the source queue record and bytes intact.
- Mount sessions now retain their shared metadata namespace through the real platform lifecycle, so transient page reads cannot close a mounted bucket's metadata worker or database. Metadata policy updates are synchronized and release callbacks are idempotent.
- A shared metadata namespace now refreshes its scoped provider transport when account credentials, access tokens, or proxy settings change, while an already-started remote request keeps a stable backend snapshot.
- Failed mount startup now closes its access/metadata resources; if a partial platform start remains live and cleanup Stop fails, the manager retains that session for retry. Legacy rename serialization also gates concurrent mkdir/delete operations, and only rebases delete targets after the remote destination is confirmed.
- Metadata worker confirmation now uses the same scoped provider snapshot as its preceding remote mutation, avoiding a credential-refresh race between upload/move and HEAD verification.
- Mounted directory and attribute reads now use the persistent inode metadata tree as their remote base across WebDAV, FUSE, WinFsp, Cloud Files, and the remote poller. Local drafts, restored writeback, directory markers, tombstones, and system overlays remain correctly layered above it.
- Metadata-backed mounted objects now retain stable platform identity: Linux FUSE/WinFsp expose their persistent OID, and Cloud Files uses a namespace-qualified OID identity while keeping remote freshness fingerprints separate for correct dehydration.
- Added a path-level metadata write facade that reserves unique content generations, journals create/write/rename/delete mutations, and prevents remote refreshes from reviving locally renamed or deleted paths while their work is pending.
- Metadata-enabled mounts now submit mkdir/upload/rename/delete through the durable inode journal instead of legacy remote queues. Worker ordering preserves write-then-rename semantics, staged-write failures/restarts cannot leave phantom pending inodes, and pending mount drafts retain their stable OID.
- Fixed write-confirmation refresh windows that could lose a pending rename's Desired inode, including first materialization of a destination containing an existing remote name; Windows Cloud Files rename completion now rebinds already-moved staged-file markers before the metadata journal worker syncs them.
- Page create/upload/rename/move/delete operations for profile-scoped buckets now enter the persistent metadata journal before any provider mutation. Page-only namespaces retain pending work after their request handle closes; permanent delete intent survives replay; mounted views project the new Desired state without deleting still-recoverable local bytes. Profile-scoped copy and recursive directory upload now fail closed until durable batch semantics are available.
- Fixed journal replay after a remote rename succeeds but target confirmation is interrupted: the durable move phase now confirms its frozen provider target rather than retries a missing source, including generic WebDAV/FTP/SFTP-style missing-source errors. Directory reconciliation requires a verified target marker/subtree instead of treating a missing source and target as success. Page-to-mount cache projection now carries an inode/revision guard, and each child write advances its parent revision so a delayed directory callback cannot hide a newer mount write.
- Profile-scoped desktop page reads now consistently use persistent metadata for paginated listings, legacy list calls, and object metadata lookups, independent of whether a mount session is active. Added page/mount shared-view, reopen, and reset-rebuild regression coverage.
- Mounted reads now serve not-yet-uploaded metadata pending content directly from its staged chunks: WebDAV/FUSE/WinFsp/Cloud Files reads never ask the provider for pending bytes, cache files materialized from chunks are pinned to the inode's content generation so an equal-size/mtime overwrite cannot serve stale bytes, and Linux/Windows fsync is local-only durability that no longer queues one remote operation per rsync write boundary.

- 修复 Windows Cloud Files 重挂载后客户端能看到文件、但 Explorer 中部分目录为空：复用缓存里的目录现在会重新启用按需枚举；如果目录已退化为普通 NTFS 目录，则原地转换回云占位目录并保留现有内容。并发目录枚举会传递真实失败结果，不再把一次失败误记为“已完整加载”。
- 修复 Windows Cloud Files 目录改名竞态：`go/mount/dir_sync_queue.go` 的 `rebaseAndFence` 现在把目录创建请求与远端改名统一排进同一个 fence；`bucket_access_writes.go` 在远端源已确认缺失时复用已改名的目标，绝不再向严格后端发送一次“源不存在”的 `MoveObject`。
- 修复 Windows Cloud Files 跨目录移动在远端出现两份（旧目录与新目录各一份）的并发错误：跨客户端移动现在持久化为 `<sessionRoot>/mutations/queue-*.jsonl` 记录（`mutation_record.go`/`mutation_store.go`），重试由观察到的源/目标状态驱动（`mutation_reconcile.go`：缺失/存在 → 收尾，存在/缺失 → 移动，存在/存在 → 拷贝+硬删，缺失/缺失 → 状态冲突重试），崩溃后下一次启动能完整收敛。
- 修复 Windows Cloud Files 闲置目录在 Linux 端写入新文件几小时后 Windows 还看不到：轮询器从“三分钟过期”改为“最多保留 12 个已观察目录、闲置则按两分钟刷新”，已经打开但闲置的目录继续按计划刷新。
- 允许为每个桶自定义 WinFsp 挂载盘符名称（留空则使用默认值）。

- Fixed mounting a bucket from a non-default account with a different Windows mount engine creating a duplicate `default` profile and duplicate bucket rows. WinFsp mounts now query the provider quota API and report its total/free values to Explorer, using the configured virtual capacity only when the provider does not expose quota data.
- Windows Cloud Files writeback now serializes uploads with directory renames, rebases local upload sources after a rename, retries remote renames, and avoids permanently suppressing watcher events below the renamed directory.

- 修复 Windows Cloud Files 重挂载后客户端能看到文件、但 Explorer 中部分目录为空：复用缓存里的目录现在会重新启用按需枚举；如果目录已退化为普通 NTFS 目录，则原地转换回云占位目录并保留现有内容。并发目录枚举会传递真实失败结果，不再把一次失败误记为“已完整加载”。
- 修复 Windows 挂载、卸载及退出清理时短暂闪出多个黑色控制台窗口：`subst`、`net use`、`sc` 和 PowerShell 辅助进程统一以隐藏且不创建控制台窗口的方式运行。
- 账号管理新增「状态」列：进入页面时并发探测每个启用账号的可达性（调用 `list_buckets`，复用已加的 3 秒拨号超时、不重试、20 秒负缓存路径，坏账号不拖累好账号），显示 正常 / 连接失败（悬停可看错误详情） / 已禁用 / 检测中。禁用账号直接标「已禁用」不发探测。
- 文件管理页某个账号暂时无法访问时，错误条的「重新配置认证信息」改为「账号管理」——点击直接跳转到账号管理页，用户可在同一处编辑、禁用或重新启用出问题的账号，不再就地弹单账号编辑器。
- 新增账号禁用：账号管理页每个账号行新增「启用/禁用」开关。禁用的账号不会出现在文件管理页/全局回收站的桶列表、不连接后端、不启动 P2P，但仍保留在账号管理页（标题标注「已禁用」），可随时重新启用。默认所有账号启用，禁用是用户主动操作。适合暂时不想连的账号（比如已知连不上的上游），避免它拖累存储桶加载。
- 修复上游不可达时仍要等满超时才返回（实测 S3 首次从 ~9s 降到 ~6s，缓存命中后 ~3s，负缓存命中后 0s）：根因有三层。① 所有 HTTP transport 没有 TCP 拨号超时，遇到丢包型不可达（网关关机、防火墙 DROP，而非 RST 拒绝）时 macOS 上要等 OS 的 TCP SYN 重试 ~75 秒，只有请求 ctx 能砍断——现在 `ProxyTransport`/`jwanfs` 统一加 3 秒 `DialContext`，S3 client 在 system/inherit 模式也改用带超时的 HTTP client。② AWS SDK 默认对 ListBuckets 重试 3 次，每次都等拨号超时——现在 ListBuckets 用不重试的 client（`NewListBucketsClient`），失败一次就进负缓存。③ JWanFS 网关探测在不可达时会 Refresh + AuthInfo 各拨一次（6s），探测超时从 10s 降到 3s（够一次拨号判定）。RST「连接拒绝」不受影响仍立即返回，3 秒超时只管丢包场景。
- 局域网 P2P 同步改为默认关闭的实验功能：之前 P2P 默认开启，在没有组播路由的网卡（en0/en1）上每 2 分钟刷一次 `no route to host`，多账号还会倍数放大。现在新账号/新配置默认 `p2pEnabled=false`，不启动 mDNS，刷屏从源头消失；已在配置里显式开启的用户保留原状。需要时可在「设置 → 局域网同步」手动打开（标注「实验功能 · 默认关闭」）。
- 修复多个上游连不上时存储桶列表仍要等很久才返回、且每次进页面都重新拨号：Go 端 `list_buckets` 现在走 `ListBucketsDedup`——singleflight 把同一账号的并发调用（文件管理 + 全局回收站 + 配额预取）合并成一次拨号，失败后按账号缓存 20 秒（负缓存），期间不再拨号直接返回上次错误。S3 `ListBuckets` 超时从 15 秒降到 8 秒。用户主动点「返回桶列表」或错误页「重试」会带 `force=true` 绕过负缓存立即重试已修复的账号。
- 修复 macOS 挂载后提示成功、但访达看不到卷、点「打开目录」卡住：根因是空挂载路径走 `osascript "mount volume"` 异步分支——它在内核登记卷后立即返回，但 webdavfs_agent 的实际握手要 ~90 秒，probe 在 mount 表提前命中并 cancel 了 osascript，卷"登记了却永远没就绪"。现在 `session.start()` 改传已解析的 `mountPath`（默认 `/Volumes/云卷-<bucket>`），统一走同步的 `/sbin/mount_webdav`——它返回时卷真正可用；osascript 分支和 `appleScriptStringLiteral` 已彻底移除。`mountWebDAV` 拒绝空路径，防止再退回 fire-and-forget。
- 修复多账号存储桶列表因某个上游连不上而整页卡死：Flutter 端 `BucketSourceService` 的 `loadProfile` 与 `listBuckets` 改为 `Future.wait` 并发、按账号 try/catch 隔离，坏账号进独立「重新配置」错误条、好账号正常显示；每个调用加 40 秒超时兜底。Go bridge `list_buckets` 用 `context.Background()` 改为 30 秒超时 ctx；S3 client 构造期的 JWanFS 网关探测（`IsJWanFSGateway`）与 `NewClient` 的 `balancer.Refresh` 此前都用无超时 ctx，不可达 endpoint 会卡在 OS 级 TCP 超时（1-2 分钟），现统一加 10 秒构造期上限，失败走已有直连 fallback。
- 修复 macOS（尤其 SFTP）点击挂载后提示成功、但访达看不到卷、再点「打开目录」无响应卡住：根因是「提速」轮询用挂载点路径名作为成功信号，而 `parseMountPoint` 解析 `mount -t webdav` 时丢弃了源 URL，导致残留同名卷、其它进程的同名卷、或请求路径分支 `MkdirAll` 出来的目录都能被误判为本次挂载成功，真正的 `mount_webdav` 反被取消。现在 `parseMountEntry` 同时保留源 URL 与路径，挂载成功判定要求源 URL（含 `127.0.0.1:<随机端口>`）严格相等，残留/同名/异端口卷一律拒绝；匹配失败会继续等真正的卷出现，超时则如实返回失败，不再误报成功。`prewarmWebDAVMount` 的 `os.Stat`/`os.ReadDir` 同时加了 30 秒上限，避免 webdavfs 卡死时泄漏后台 goroutine。
- 修复 macOS P2P mDNS 在没有组播路由的 `en0`/`en1` 上持续刷 `no route to host`：对 `ENETUNREACH`/`EHOSTUNREACH` 按接口共享 2 分钟退避，同一故障不再随多账号和 30 秒发现周期重复刷日志；网络恢复后自动重试。
- 修复 macOS 挂载后「打开目录」卡住约 90 秒无响应：Finder 打开 WebDAV 卷时 `open` 命令的 stdout/stderr 被 LaunchServices 继承，`CombinedOutput` 即使在 context 超时后仍被管道阻塞。改为完全分离进程（Stdout/Stderr → /dev/null + Setpgid），最多等 3 秒即返回，Finder 在后台异步出现。
- 修复 Finder/Spotlight 递归扫描后 SFTP 挂载持续刷新深层目录：SFTP 现在关闭 P0 后台远端目录轮询，避免每 5 秒为最多 12 个活跃路径重复建立 SSH/SFTP 连接并挤占写回链路；用户主动打开目录仍按需读取。挂载配额缓存过期后不再丢弃最后一次已知容量，首次 WebDAV `PROPFIND` 会立即使用旧值、异步刷新，并在刷新暂时失败时继续保留可用容量。
- 修复 macOS WebDAV 挂载向 SFTP 上游写入小文件异常缓慢：Finder 的 `PROPPATCH` 元数据探测不再误走内容暂存/下载/回写流程，新建目录或新鲜目录列表内的目标缺失探测也直接由本地视图返回，不再为每个文件同步建立 SFTP 连接做 `stat`；正常 `PUT` 仍先写本地缓存并按单文件 quiet period 异步上传。SFTP 上传会同步更新共享传输任务的进度与完成/失败状态，不再在远端已写入、持久化队列已清空后仍显示“等待同步”长达 10 分钟。
- macOS WebDAV 挂载根目录现在通过 RFC 4331 返回 `quota-available-bytes` 与 `quota-used-bytes`，优先使用桶自定义容量并复用上游实际配额/已用量，让 `df` 不再在已有容量信息时显示 `0/0`。桶列表的配额结果现在同时进入 Go 后端 5 分钟共享缓存；缓存身份只包含协议、endpoint、凭据、端口、provider 与代理等上游连接字段，缓存目录、RootPrefix、挂载参数或显示设置不同仍可初始化首次 `PROPFIND`。无缓存时仍立即挂载并异步刷新。
- 修复 macOS 显示“正在处理挂载”固定约 20 秒：`osascript` / `mount_webdav` 执行期间并行轮询 WebDAV mount 表，卷一出现就取消命令并返回，不再等命令超时。Finder 打开请求改为异步单飞，重复点击不会堆积多个不可中断的 `open` 进程；卸载先断开系统卷，成功后才停止本地 WebDAV，卸载失败会保留服务和会话，避免形成无后端死卷。SFTP SSH 建连与握手也改为响应请求上下文，目录枚举不会突破挂载层超时。
- FTP 与 WebDAV 上游上传现在和 SFTP 共用传输任务跟踪器，按读取字节更新进度并在成功/失败时结束任务；挂载写回完成后不再残留 10 分钟的“等待同步”状态。
- 修复多账号 P2P 发现互相不可见：4 个账号各自创建独立的 mDNS Server 导致 UDP 5353 端口冲突，实际只有部分指纹在广播。改为共享一个 mDNS socket，多个账号指纹复用同一端口注册各自的 SRV/TXT 记录；同时禁用 IPv6 mDNS 查询并静默 hashicorp/mdns 的 IPv6 监听失败日志，消除无 IPv6 路由环境下的错误刷屏。
- 修复多网卡设备发现不到对端：mDNS 查询不再只走默认网卡，改为对所有有 IPv4 地址且支持组播的网卡分别查询，解决 VMware 桥接虚拟机绑在副网卡（如 en1）时宿主主机发现不到的问题。
- 修复局域网 P2P 多账号发现的指纹不稳定问题：manager 生命周期不再对整个配置 JSON 做哈希（配置里的时间戳、缓存目录等非凭证字段会导致备份还原后指纹变化），改为只对存储类型 + endpoint + 账号 + 密钥做哈希，时间戳变化不再影响发现。
- 局域网 P2P 多账号并行发现：bridge 不再只为活跃账号维护单个 PeerManager，而是为每个启用 P2P 的账号档案各注册一条 mDNS 服务（独立 QUIC 端口），两台设备只要共享任意一个账号即可互相发现，与当前活跃账号无关。变更广播/内容拉取按发起方账号指纹路由到对应 manager；设置页设备列表聚合展示并标注与每台对端共享的账号；P2P 开关仍按账号档案独立保存。修复了多账号环境下（例如两台设备活跃账号不同）「暂无已发现设备」的问题。
 - 设置页「局域网同步」卡片视觉对齐其他设置卡片：顶部说明文字 + secondary 容器开关行 + 统一的 _SectionHeader 分组标题，去掉孤立的 textTheme.h4 排版；设备列表改为 secondary 容器 + 中性图标 + 在线状态点。
- 修复局域网 P2P 启动时错误地将 `_tcp` 作为 mDNS 域名传入，导致 mDNS 注册失败并持续显示 bootstrap error；现在按 `_cloudvolume._tcp` 服务和 `local.` 域名正确注册与查询。
- Windows 挂载：WinFsp 虚拟文件系统改为只允许盘符挂载。挂载弹窗在选择 WinFsp 时隐藏路径挂载；没有空闲盘符时禁用提交，Go 后端也会拒绝绕过 UI 传入的目录挂载请求，避免驱动挂载失败。
- 局域网 P2P 同步（D1/D2）：同局域网内登录同一账号的多台设备通过 mDNS 自动发现（`hashicorp/mdns`），无需配对或扫码。远端确认后的写入、删除、重命名会通过 QUIC（`quic-go`）立即通知对端刷新受影响目录；D2 读取优先向发现的设备查询同版本内容，并以可配置的 1–64 MB 原始字节分块、最多 4 路并发直传到普通读缓存。S3 使用 ETag，其他后端回退到修改时间 + 文件大小；账号 secret 派生 HMAC 认证事件、请求、响应和每个字节分块，且接收端在完成后重新校验远端版本；任一发现、鉴权、传输或版本校验失败均自动回退远端。设置页可关闭 P2P、配置分块大小并查看已发现设备。
- 配置备份还原：统一设置页历史与首次启动两条路径为“先确认、失败再要密码”。解密失败判定收紧到 Go 稳定文案；本地密码已失败时不再用同一密码重试一轮；取消密码输入用 `ConfigBackupRestoreCancelled` 静默退出，不再靠中文字符串匹配；空密码提交在弹窗内提示。设置分组侧栏改为 常规 / 网络 / 存储 / 账号 / Windows / 关于。
- 配置备份：设置页新增加密远端配置备份。加密密钥改为从用户自设的备份密码派生（不再依赖连接凭证，换机器、换 endpoint 都能解密），开启备份时必须设置密码。新机器首次启动可从备份存储还原。顶部「开启备份」开关控制功能启停；开启后才显示备份存储设置，目标可选已有账号或走简化流程配置独立备份存储（仅选协议+连接凭证，不显示在账号列表）。保存位置改为单个远程目录选择器一次选定 bucket 与目录，移除了两个手动输入框。备份历史通过可点击摘要卡片打开拟态框查看，并支持二次确认还原账号、全局代理和显示排序。首次启动的「从备份存储还原」入口如检测到本地无已配置备份目标，会先引导连接一个备份存储（选协议+填凭证+选保存位置），再用该临时目标列出远端快照并还原；备份列表会探测每个快照的加密状态，加密快照显示锁标识并在还原前提示输入备份密码（密码会随还原结果一起写入系统设置）；还原成功后该备份存储（含备份密码）自动写入系统设置并开启自动备份，后续配置变更继续备份到同一位置。
- 挂载同步：新增 P0 远端轮询兜底。挂载会话只刷新近期打开的目录，活跃轮询间隔可在「设置 → 同步设置」配置（默认 5 秒、范围 1 秒至 5 分钟），并自动退避；文件管理列表会对所有活动挂载（包括 WebDAV）复用同一份 local-first 目录视图，并以短时稳定快照分页，避免待写回条目与挂载盘显示不一致、目录变化时翻页重复或漏项。Windows Cloud Files 将其他客户端新建的条目投影为占位符，Linux FUSE、WinFsp 和 WebDAV 在下一次读取目录时使用新缓存。不会后台扫描整桶或丢弃本地待写回项。
- Windows 挂载：严格只读挂载改为强制 WinFsp，Cloud Files 后端拒绝伪只读会话；卸载确认框新增打开文件风险说明和“同时删除默认 Cloud Files 本地缓存”选择。文件仍被占用时，挂载会安全解除并在状态中提示缓存未能清理。
- Windows Cloud Files：远端轮询和 Explorer 的重复目录请求现在会用 `CfUpdatePlaceholder` 更新已存在的占位符元数据，并将远端变更的文件脱水，下一次读取重新拉取内容；新建和远端删除也会投影到已打开目录。待写回或正在上传的本地文件始终跳过，避免跨端刷新覆盖本地修改。
- Windows 挂载容量：Cloud Files 不再提供 `subst` 映射盘符，因为该入口只能显示宿主磁盘容量。需要在资源管理器显示桶级配额时，挂载对话框会引导使用 WinFsp 虚拟卷及盘符。
- Windows 重挂载：强制卸载后若 Explorer/Office 等仍占用 Cloud Files 缓存，陈旧清理会注销同步根但保留无法删除的目录，下一次挂载复用该稳定根目录而不再失败。
- Linux 挂载权限：FUSE 根目录、目录项和文件属性现在显式使用当前进程 UID/GID，与 `default_permissions` 配合，避免 Windows 端写入后 Linux 挂载显示为 root 所有并拒绝当前用户修改。
- 文件操作：Windows 外部应用打开不再把文件路径作为带引号的 `cmd start` 参数传递，修复预览/打开缓存文件时提示找不到路径；复制、移动改为远端目录选择器，选定目录后自动保留源文件名。
- 对象重命名：目录重命名复制成功后直接删除复制计划中捕获的源键集合，不再重新列举源前缀，避免 S3 兼容服务的延迟列表让旧文件与新文件并存。
- 回收站：恢复操作现在携带原始路径和目录标识通知活动挂载，清除 tombstone 并重新投影 Cloud Files 占位符，恢复后的文件/目录可继续删除和重命名。
- 账号：编辑时未填写的 Secret/密码会保持已保存值；修改 S3 AK/SK 后显示独立鉴权按钮，验证失败不会覆盖原账号配置。文件管理桶聚合改为单账号鉴权失败不阻塞其他账号，并提供针对失效账号的重新配置入口。
- 修复 FTP/SFTP 与配额加载回归：SFTP 删除目录现在递归清理非空子树；桶配额请求继续并发执行，并限制每项 10 秒，避免单个不可用账户无限阻塞桶列表；带 `RootPrefix` 的后端保留配额能力转发并新增回归测试。既有 S3 调用统一经 JWanFS failover SDK 选择活动网关，随后继续使用 AWS SDK v2 执行实际请求。
- 新增 FTP / SFTP 后端：支持经典 FTP（jlaffaye/ftp）和 SFTP（pkg/sftp + ssh）两种远端存储类型，包含独立于 WebDAV 的用户名/密码字段、自定义端口、匿名登录开关。SFTP 通过 statvfs@openssh.com 扩展读取服务端配额；FTP 协议无标准配额命令，暂报告容量未知。两种后端均支持完整的文件管理操作（列表、上传/下载、目录创建/删除、重命名、移动、复制、范围读取），暂不支持应用级回收站（FTP/SFTP 服务器自身管理删除语义）。Mock 测试服务器分别基于 ftpserverlib（FTP）和自研共享内存 SFTP handler（SFTP）实现进程内完整协议测试。
- 修复桶列表 hover 失效：配额刷新不再在首帧渲染后用第二次 `setState` 替换 `_buckets`，而是合并进 `_loadBuckets` 的单次 `setState`，避免 `FileListTile` 子树被重建导致 `_hovered` 丢失（“hover又坏了”回归）。
- S3 目录软删除：部分兼容服务在递归列举时会返回目录内文件、却省略目录自身的 `dir/` 占位对象，导致子文件已移入回收站但源目录占位仍留在远端，应用重启后重新显示为空目录。目录变更计划现在始终显式包含根目录占位 key，复制阶段在回收站保留完整目录语义，源清理阶段幂等删除该 key。
- 回收站：批量选中后不再显示冗余的“清空选择”操作，并统一普通态与多选态的按钮尺寸，避免顶部操作区高度跳变；仍可通过列表行或表头复选框取消选择。
- 回收站子目录视图（方案 1）：配置了子目录（`RootPrefix`）的桶，回收站现在落在该子目录下（`<rootPrefix>/.trash/...`）而不是桶根的 `.trash/`。每个子目录视图各自拥有独立回收站，互不污染。`trashPrefix` / `webDAVTrashPrefix` 把 RootPrefix 纳入路径；`isTrashKey` / `isRootTrashKey` / 挂载层 `isTrashPath` / WebDAV `webDAVIsTrashKey` / `webDAVIsTrashRootEntry` 改成按带 RootPrefix 的全路径匹配，避免把子目录下的回收站当作普通目录；`scopedBackend.ListTrashPage` 因为 trash 本身就在视图根下，改为只做 OriginalKey 相对化改写、不再按 root 过滤。
- 重构：桶列表加载抽成共享的 `BucketSourceService`（`lib/services/bucket_source_service.dart`）。文件管理首页和全局回收站现在共用同一套"枚举所有账号 → 各自 list_buckets → 应用每账号 allowlist → 按已保存顺序排序"的逻辑，回收站看到的桶集合和文件首页完全一致；之前回收站自己重新实现了一遍单账号子集，既看不到其他账号的桶，也绕过了桶可见性设置。`FileManagerPage` 的旧聚合逻辑改为薄壳委托给 service，对外异常类型保持不变。
- 全局回收站：桶筛选下拉框、清空回收站确认弹窗、空状态文案现在统一显示桶的友好名称（用户在桶管理里设置的自定义显示名，未设置则回退真实桶名），和文件管理首页一致；之前显示的是内部 `profile::bucket` id。`GlobalTrashFilters` 的 `bucketOptions` 从 `List<String>` 改成 `List<GlobalTrashBucketOption>`（id + label），避免在多个地方各自反查 label。
- 全局回收站：接入多账号聚合，`GlobalTrashPage` 新增 `profiles` 参数，`main_layout_page` 已把 `widget.state.profiles` 一并传入。每个 trash entry 现在携带所属账号的 `RemoteStorageConfig`（含合并后的 root prefix），恢复 / 彻底删除 / 清空回收站都按对应账号的凭据和前缀调用后端，不再混用活动账号配置。回收站刷新也会在 profiles 变化时触发。
- 账号管理：账号行操作按钮从 shadcn `ShadButton.ghost` 改为自绘的 `_AccountActionButton`（独立 StatefulWidget + `_hovered` + MouseRegion + AnimatedContainer + `ListInteractionColors.rowBackground`）。原 ghost 按钮自带 `colorScheme.accent` hover 背景，比文件列表行的中性 wash 强很多，新增「桶管理」第四个按钮后 hover 叠加非常明显；自绘后 hover 只是轻微背景变化，和文件管理行视觉一致，符合 AGENTS.md hover 规则。
- 账号管理：桶管理按钮文案从「桶可见」改为「桶管理」，toast 文案同步改为「桶管理已更新」。
- Windows CI：修复 Inno Setup 打包因 WinFsp MSI 路径被解析为 `scripts/go/mount/...` 而失败的问题。`build_windows_installer` 现在向 ISCC 传绝对 Windows 路径的 `WinFspMsiPath`（不再回退到 `.iss` 默认相对路径），并在 MSI 缺失时立即失败、给出清晰错误信息。
- 账号管理：桶列表显示设置从编辑账号里拆出来，成为独立的「桶管理」入口。账号列表（表格和卡片视图）每行新增「桶管理」按钮，点开只做一件事：列出该账号全部桶，勾选作为 allowlist、可改显示名和子目录，保存即生效，不触碰连接信息也不会触发 list_buckets 之外的远端调用。
- 账号管理：编辑账号恢复为只编辑连接信息的单页表单，「下一步」不再尝试拉取桶列表（之前的实现会在编辑模式调用 list_buckets 导致 "static credentials are empty" 错误）。
- 账号管理：删除账号时自动级联删除该账号下所有目录同步任务，并在「账号已退出」提示里标注删除的同步任务数量；同步任务运行时会先 Reload 停掉对应 runner 再删除记录，避免孤儿任务继续轮询已失效凭据。
- 桶可见性：向导第三步和独立桶管理弹窗的 Checkbox 都改为自绘的 `BucketSelectionCheckbox`（原 `_BucketSelectionCheckbox` 提为 public），修复在 ShadDialog（无 Material 祖先）子树中抛出 "No Material widget found" 以及连带 RenderFlex 99430px 溢出的问题。
- 新增账号向导增加第三步“桶列表显示设置”，S3、WebDAV、百度网盘统一支持。默认不勾选任何桶时动态显示全部桶并自动包含服务端后续新增桶；一旦勾选则作为显式 allowlist。每个选中桶可设置自定义显示名称并通过远程目录选择器限定入口子目录，文件浏览、写操作、回收站、同步与挂载共用同一前缀映射。
- 修复新增账号桶可见性引入的几个回归：scoped 回收站列表不再别名 provider 切片（避免污染缓存或索引）、挂载层与 `scopedBackend` 不再双重叠加 `RootPrefix`（修复配置子目录后挂载指向错误路径）、目录选择器现在沿用账号级 `RootPrefix`。
- 文件管理桶配额新增页面会话缓存：成功结果 5 分钟内复用，进入桶后返回列表不再重复请求；缓存过期时保留旧值并在后台刷新，账号凭据或 quota 相关配置变化后会自动失效。
- 桶列表在窄内容区仍保留“操作”列；空间不足时优先收起独立“来源”列，并在名称副标题继续显示账号来源。
- 文件管理桶卡片模式不再渲染容量字幕和进度条，避免固定高度卡片溢出；列表模式继续显示完整“已用 / 配额”列。
- 百度网盘账号编辑/恢复流程提交授权码成功后会自动保存新 OAuth 凭据并关闭拟态框，不再要求再次点击“保存修改”。
- 文件管理认证失败时，“重新配置认证信息”现在打开统一的账号编辑拟态框：桶首页加载失败会定位到失败来源，点击某个桶后对象列表失败会直接定位到该桶所属账号，不再跳转到首次运行初始化页或误编辑第一个账号；并发桶加载只允许最新一代更新错误状态，账号管理与文件管理共用账号编辑 presenter。
- 存储配额：桶列表首帧渲染后，每个条目都必须通过独立 `get_bucket_quota` bridge 请求刷新配额，不再依赖运行时可选接口或前端存储类型过滤；百度网盘/WebDAV 查询远端，S3 在后端直接返回未知。百度 quota 返回“用户未登录”时会立即刷新 OAuth token 并重试，无需先进入文件列表触发认证；刷新后的 token 会按实际百度 profile 写回，不再错误地只尝试更新当前活动的 S3 账号。记录列表入口及 quota 请求开始、成功和失败日志，Flutter/FFI 入口失败也会记录 error；Debug 构建强制启用 debug 日志，后端 error 在“安静”级别下仍会落盘。百度网盘请求显式携带 `checkfree=1` / `checkexpire=1`。
- Windows 应用图标现在通过脚本应用更接近 macOS 的 22.5% 透明圆角遮罩，并在 ICO 中提供 16–256px 的常用尺寸图层，改善任务栏、开始菜单和资源管理器中的轮廓与缩放清晰度。
- 文件管理配额：WebDAV 根目录现在通过 RFC 4331 的 `quota-available-bytes` / `quota-used-bytes` 获取真实已用/总容量，百度网盘通过 xpan Quota API 获取账号已用/总容量；桶列表“已用 / 配额”列和网格卡片始终显示容量进度条，有真实用量时按比例填充，仅配置总额度的 S3 等后端显示“用量未知”，完全没有总额度时显示“未设置额度”，两者都保留中性空轨道。自定义配额仅覆盖总量，不影响文件浏览。
- 删除进度修复：多对象删除任务成功完成时，前端立即将已处理对象数同步到总数，避免完成弹窗短暂显示“已完成”但仍为 `10 / 20`，等待下一次轮询后才变成 `20 / 20`。
- 删除状态修复：文件或目录删除成功后，文件管理列表立即移除对应行并清理“删除中”状态；即使紧接着的远端/挂载列表刷新短暂返回旧 key，也不会让已完成的删除重新卡在列表中。
- 跨平台构建修复：WinFsp bridge 方法改为仅在 Windows 构建中注册和编译，修复 Windows 挂载功能合入后 macOS/Linux 因引用 Windows 专用符号而无法执行 `go test` 或构建 bridge 的问题。
- 挂载容量：桶级自定义配额现在同步到 Windows WinFsp 与 Linux FUSE 的 `Statfs` 总容量/可用容量；WinFsp 在桶未设置配额时继续使用 Windows 高级设置中的全局虚拟容量。Cloud Files/WebDAV 不走应用自有 `Statfs`，不受影响；修改配额后重新挂载生效。
- 文件管理：桶列表新增“配额”列，网格卡片也会显示已配置容量；“桶设置”新增自定义配额（GB）输入，支持小数并按桶持久化。0 或留空表示未设置，列表显示 `--`；该值仅用于容量标注，不会限制上传。
- Windows 启动可靠性：发布包新增独立 `cloud-volume.exe` 启动器/守护进程，实际 Flutter 主程序改为 `cloud-volume-app.exe`。即使主程序在 Windows Loader、Flutter 引擎或首个窗口创建前异常退出，守护仍会记录退出码，生成包含系统版本、关键二进制 SHA-256、bridge 日志尾部和最近 updater 日志的崩溃报告到 `~/.cloud-volume/runtime/crashes/`，并提示用户检查后提交给开发者；正常退出和应用更新的退出码为 0，不弹崩溃提示。
- 删除体验：文件管理页的删除确认拟态框新增「永久删除」开关（仅在桶开启回收站时显示），勾选后绕过回收站直接彻底删除；未勾选时按桶设置移入回收站，弹窗文案也随是否启用回收站区分「移入回收站/不可撤销」。
- 删除体验：目录删除（软删除、永久删除、彻底删除回收站项、跨目录移动/重命名的源清理）现在按对象数实时上报进度，批量删除进度拟态框与任务队列显示确定的进度条和「已处理 / 总数 个对象」，不再一直是无限加载状态。
- 移动/重命名修复：复制完成后的源对象清理改为删除「枚举时记录的完整 key 列表」，不再依赖任何二次前缀列举，修复移动或重命名目录后旧位置偶发残留文件/目录的问题。
- 删除进度修正：软删除（移入回收站）的进度改为分阶段统计（复制阶段 + 源清理阶段各自从 0 计到对象总数），修复进度拟态框中「206 / 103 个对象」这类已完成数超过总数的问题；源清理阶段任务会标记「正在删除源对象」，任务完成后数量始终显示为 总数 / 总数。
- S3 删除/移动/重命名容错：软删除（移入回收站）、复制、移动和重命名时，逐对象的 CopyObject、目录占位符 PutObject、HeadObject 与源对象 DeleteObject 现在使用单次调用的扩展重试预算（5 次尝试、退避上限 15s），并对 S3 兼容网关偶发的非可重试错误（如 CopyObject 的 InvalidArgument 毛刺、连接重置）再做少量间隔重试。网关或代理返回 502 HTML 错误页等瞬时故障时，单个对象不再直接中止整个目录的删除/移动操作。
- Windows window chrome: the existing `window_manager` integration now solely owns hidden-titlebar non-client handling plus native maximize/restore/minimize/drag commands. The runner keeps the default overlapped style and only owns tray/exit behavior, removing the competing popup/frame implementations that exposed black or white resize frames and could show a native title bar. The window class now registers a light-surface background brush, so the maximize/restore transition no longer flashes black before Flutter presents the resized frame (a transparent/layered window cannot work with the Direct3D Flutter child).
- Windows 构建：移除 `winfsp` build tag 门槛——WinFsp 引擎现在随每个 Windows CGO bridge 构建一起编译。`third_party/winfsp/inc/fuse` 头文件已入库，`run_windows.ps1`、`build_desktop_packages.sh`、`windows/CMakeLists.txt` 与 `Makefile bridge-windows` 都会设置 `CPATH` 指向它，CI 与本地构建都会默认带上 WinFsp 引擎。
- 测试：修复 `transfers_page_batch_actions_test.dart` 和 `widget_test.dart` 中 fake API 实现遗漏的方法签名，使此前被跳过的 4 个测试重新通过。
- Windows 挂载高级设置：新增挂载内核选择（Cloud Files 默认 / WinFsp 虚拟文件系统）。WinFsp 模式在 Explorer 中呈现真实卷，可自定义虚拟总容量；驱动缺失时设置页和挂载弹窗都会提示并支持一键静默安装（仓库已内嵌 `winfsp.msi`，约 2.1 MB）。
- Windows 构建：bridge 在检测到 `third_party/winfsp/inc/fuse` 头文件时自动加上 `-tags winfsp` 构建 WinFsp 引擎；未安装 WinFsp 时默认构建仅保留 Cloud Files，不影响现有开发流程。
- Windows 打包：Inno Setup 安装器新增可选的「安装 WinFsp」勾选项，并把 `winfsp.msi` 一并放到 `{app}\winfsp`，方便应用内安装复用。
- Windows Cloud Files: the mount dialog now uses a read-only switch plus a Windows-only presentation selector for “分配盘符” or “路径挂载”. Drive mode is the default when available, lists every free letter from `Z:` through `D:` for explicit selection, and unmount/remount/normal exit remove only mappings whose target still matches the managed Cloud Files path.
- Windows Cloud Files: the drive selector now opens without scrolling the modal to its last row, and an inline note clarifies that the drive is a local sync-directory mapping rather than a representation of the cloud account's real capacity.
- Windows exit: confirmed window exit and tray-menu Exit now hide the window/tray immediately, then clean active mounts in the background before process termination, so Cloud Files providers disconnect and deregister during normal shutdown.
- Windows exit: avoid broadcasting a global Explorer association refresh when no managed This PC namespace entry changed.
- Desktop exit: when mounts are active, the close dialog now warns that Exit will unmount them and labels the keep-alive action "后台运行".
- Desktop exit: always show minimize/hide-to-tray versus Exit choices, even when no mounts are active.
- Windows Cloud Files: deleting a file or directory from the app file list now removes the existing sync-root placeholder immediately, cancels pending mount writeback that could recreate the object, and suppresses provider-owned delete callbacks so the removal is not sent to the remote backend twice.
- Windows Cloud Files: app-side directory creation, uploads, copies, and moves now project new or overwritten remote objects into the sync root as placeholders when their parent directory is present.
- Windows 设置：移除已失效的“此电脑”云卷入口卡片及左侧锚点，保留旧配置字段用于兼容已有配置文件。
- 首次启动配置：步骤切换改为左侧品牌面板宽度收缩 + 右侧内容淡入（约 240ms），去掉中间 loading 占位，避免二次重建导致掉帧。
- 首次启动配置：添加存储账号第二步（连接信息）改为全屏表单，隐藏左侧品牌宣传；宽屏下 S3 / WebDAV 字段两列排布，减少单页滚动。第一步协议选择仍保留左右分栏。
- 首次启动配置：S3 默认网关 `https://fgws3-ocloud.ihep.ac.cn`，WebDAV 默认网关 `https://webdav-ocloud.ihep.ac.cn`（用户已手改地址时不会被协议切换覆盖）。布局铺满标题栏下方，不为桌面拖拽区额外加顶部白边。
- Windows ARM64 Flutter 构建：环境脚本新增原生 Rustup 工具链，运行脚本自动加入 `%USERPROFILE%\.cargo\bin` 并开启 CargoKit 详细日志；`super_native_extensions` 等 Rust 插件会优先本地编译，不再因 GitHub Release 预编译 DLL 间歇性超时而只报模糊的 MSB8066。
- Windows ARM64 开发：安装脚本会校验并安装 Visual Studio `VC.Tools.ARM64`，且以 MSBuild `Platforms\ARM64` 是否存在作为就绪条件；`run_windows.ps1` 在启动 Flutter 前预检该工具集，缺失时给出明确安装命令。
- Windows ARM64 cgo：Cloud Files 挂载相关文件的 `#cgo CFLAGS` 不再硬编码 `_AMD64_`，改为按 `amd64`/`arm64` 分别定义架构宏，修复 ARM64 下 `windows.h` 内联汇编与 `CONTEXT` 重定义错误。
- Windows 启动脚本：修复 `Resolve-Executable` 把裸命令名 `go` 误解析为仓库根目录 `go/` 包目录的问题，避免 bridge 构建时执行目录而非 `go.exe`。
- Windows ARM64 工具链探测：`run_windows.ps1` 改为用 `ProcessStartInfo` 读取编译器 `-dumpmachine`，避免 PowerShell 调用算子在 ARM 主机上空输出导致已安装的 CLANGARM64 识别失败；并优先使用 `clangarm64` 路径、自动纠正陈旧的 `BRIDGE_CC`。
- Windows ARM64 开发：环境安装、bridge 构建、Flutter release 输出和 Inno Setup 打包现已按本机架构自适应。x64 继续使用 MSYS2 UCRT64 GCC，ARM64 改用 CLANGARM64 Clang，并在构建前校验 cgo 编译器 target，避免 ARM64 汇编被误交给 x86_64 assembler。
- Windows 开发环境：安装脚本会在未配置自定义 Go 模块代理时设置 `GOPROXY=https://goproxy.cn,direct`，提升国内网络下依赖下载的可靠性；已有自定义代理保持不变。
- 账号管理 / 文件管理：列表视图支持拖拽排序。
- 启动刷新：`AppBootstrapPage` 在已进入主界面后的 `onRefresh` 改为静默替换 bootstrap 会话，不再走 FutureBuilder 全屏“正在检查配置”，避免账号拖拽排序等操作闪一下。账号顺序与桶顺序写入 bbolt `meta`（`profile_order` / `bucket_order`），重启后保持；卡片视图仍不支持拖拽。搜索中或回收站首页的桶列表禁用排序。

- 模态 UI：默认统一为应用内拟态框（`showAppModal` / `showAppConfirmModal`）。账号新增/编辑、同步配置、远端目录选择不再默认打开 OS 子窗口；`desktop_multi_window` 子窗口仅 Debug + `--dart-define=USE_MODAL_SUB_WINDOWS=true` 可用。业务侧禁止直接 `showShadDialog`。


- Account editor sub-window resizes to measured form content (no step-0 empty bottom / step-1 inner scroll when screen allows).

- 账号新增引导：新增账号改为两步式引导——先选择接入协议（S3 对象存储 / WebDAV / 百度网盘），再填写对应的连接信息。协议选择改为卡片式布局（图标 + 名称 + 说明），选中后点击「下一步」进入字段配置。编辑模式跳过协议选择，直接进入连接信息。子窗口尺寸随步骤自动调整。
- 账号代理：每个账号渠道现在可以单独配置代理（跟随全局 / 跟随系统 / 直连 / 自定义 HTTP 或 SOCKS5），不配置时默认跟随设置中的全局代理。全局代理改为独立存储（bbolt `meta` bucket），不再覆盖各账号自身的代理字段。百度网盘 SDK 升级到 xpan v0.2.0，支持 per-account HTTP client 和凭据隔离，多个百度账号可各自走不同代理。

- Windows 打包：新增 scripts/build_windows_installer.bat 和 uild_windows_installer.ps1，双击即可从 release 目录打包出 yunjuan-windows-amd64-installer.exe。setup_windows_dev.ps1 也新增了 Inno Setup 6 自动安装步骤。
- 页面头部布局：修复任务队列、分享管理、回收站等页面选中多项后右侧操作按钮挤压标题，导致副标题错位断行（如「回任务。」）的问题。新增通用 `PageHeaderActions` 组件，宽度不足时把次要操作收进「…」更多操作下拉菜单（复用 `ShadContextMenu` 模式），标题列改用 `Flexible` 并给副标题加 `maxLines` 兜底。所有列表页头部统一这一响应式折叠逻辑。

- 挂载同步：修复在文件管理界面删除/重命名/移动/复制/建目录/上传后，挂载点（Finder/WebDAV）仍显示幽灵文件、界面列表卡在"删除中"的问题。根因是 bridge/webapi 的远端 mutation 直接改后端对象却不通知 `go/mount` 的 `bucketCache`，而文件管理列表加载（`list_object_page`）在挂载活跃时会优先读挂载缓存。现在 bridge 与 webapi 的所有外部 mutation 在成功后会调用新增的 `bucketmount.NotifyExternalDelete`/`NotifyExternalUpload`/`NotifyExternalRename`，同步失效挂载 session 的 `listCache`/`objectCache`/`localEntries`/`deletedPaths`，让文件管理与挂载点视图立即一致。

- 应用更新：Windows 绿色版 zip 更新改用独立 `cloud-volume-updater.exe` 替代 PowerShell 脚本。updater 是纯 Go 编译的独立 exe，启动后会显示"正在更新云卷，请稍候..."进度窗口，等待旧进程退出、解压覆盖文件并重新启动应用。相比之前的隐藏 PowerShell 脚本，它不受执行策略影响、不会静默失败、且给用户可见的更新反馈。updater exe 会打包进 release zip 和 installer。

- 应用更新：Windows 绿色版 zip 更新改用独立 `cloud-volume-updater.exe` 替代 PowerShell 脚本。updater 是纯 Go 编译的独立 exe，从下载的 zip 包内动态提取到临时目录运行，旧版本无需预装。启动后显示"正在更新云卷，请稍候..."进度窗口，等待旧进程退出、解压覆盖文件并重新启动应用。相比之前的隐藏 PowerShell 脚本，它不受执行策略影响、不会静默失败、且给用户可见的更新反馈。updater exe 会打包进 release zip。

- 应用更新：修复 Windows 绿色版 zip 更新覆盖文件失败的问题。根因是 updater 脚本等待进程退出后没有二次确认 `cloud-volume.exe` 的文件锁已释放，如果后台/子进程仍占用 DLL，`Copy-Item` 静默失败，旧文件被保留。现在 updater 会轮询等待 exe 可写后再覆盖，并将每步进度和错误写入 `%TEMP%\cloud-volume-update-<pid>.log` 便于排查。
- 应用更新：重写 Windows cloud-volume-updater.exe 的进度窗口。新窗口使用 Win32 自绘（非 MessageBox），匹配项目视觉风格——浅色背景、Microsoft YaHei UI 字体、"云卷"品牌字样、当前步骤文案、分段进度条，并在 Windows 11 上请求 DWM 原生圆角。updater 现在会将每一步写入 %TEMP%\cloud-volume-updater-<pid>.log（解压路径、覆盖结果、新进程 PID），并在确认新 cloud-volume.exe 进程真正启动后才退出，避免重启竞态导致更新静默失败。

- 应用更新：修复「跟随系统」代理模式下检查更新不走 Windows 系统代理的问题。根因是 Dart 的 `HttpClient.findProxyFromEnvironment` 只读 `http_proxy`/`https_proxy` 环境变量，不读 Windows 设置里的手动代理。现在桌面端新增 bridge 方法 `resolve_system_proxy`，由 Go 读取 `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings` 注册表的 `ProxyEnable`/`ProxyServer`，Dart 在 system 模式下先查它，命中后当 HTTP/SOCKS5 代理用于检查更新和安装下载。

- Windows 构建：`scripts/run_windows.ps1 -Build` 和双击 `scripts/build_windows.bat` 现在会把 `git describe --tags --always --dirty` 写入 `APP_VERSION_LABEL`，不再产出应用内更新无法比较的 `dev` 版本；需要手动指定时可传 `-Version 1.2.3`。`make build-windows` 也改为和 macOS 一样使用 Git 版本标签。

- 应用更新：Windows 一键更新现在优先使用绿色版 `yunjuan-windows-amd64.zip`，启动临时 PowerShell updater 等待当前进程退出，解压覆盖当前应用目录并重新启动 `cloud-volume.exe`；如果 Release 只有 Inno Setup `installer.exe`，仍会回退到静默安装器更新。

- Windows desktop close flow: fixed the confirmed "Exit Yunjuan" action from the close confirmation dialog and tray menu. Confirmed exits now use a dedicated native `exitApp` channel that bypasses the tray `WM_CLOSE` interception, while ordinary close gestures still show the hide-to-tray versus exit prompt.

- Windows 开发环境：新增 `scripts/setup_windows_dev.bat` 双击入口，并新增 `scripts/setup_windows_dev.ps1` 用于新 Windows 机器一键准备本地开发依赖。脚本会通过 `winget` 安装/校验 Git、Go、Visual Studio 2022 Build Tools、MSYS2；没有 `winget` 时，VS Build Tools 和 MSYS2 会回退到官方安装器直链静默安装。脚本会 clone Flutter stable 到 `$HOME\dev\flutter`，安装 MSYS2 UCRT64 `gcc/g++`，写入 `FLUTTER_ROOT` / `BRIDGE_CC` / `BRIDGE_CXX` 和用户 `PATH`，并可通过 `-ValidateProject` 调用现有 `scripts/run_windows.ps1 -Build` 做项目构建验证。针对当前 Windows 环境还补了两处安装韧性：接受 VS 安装器 `3010`（安装成功、需要重启）退出码；Flutter cache 缺少 `dart.exe` 时直接下载对应 Dart SDK 修复首次 bootstrap 卡死。

- Windows 开发环境：新增 `scripts/run_windows_debug.bat` 和 `scripts/build_windows.bat` 双击入口，分别用于一键 Debug 运行和 Release 构建。三个 Windows 双击入口统一放在 `scripts/` 下，底层都复用现有 PowerShell 工作流。

- Windows 开发环境：修复 Flutter 目录由管理员创建时 Git 报 `detected dubious ownership`，导致 Flutter 无法确定 engine version 但脚本仍显示完成的问题。`setup_windows_dev.ps1` 和 `run_windows.ps1` 现在会自动将 Flutter 根目录加入当前用户的 Git `safe.directory`，并统一检查 Flutter/Go/MSYS2 等外部命令退出码，失败时正确中止。

- Windows 开发环境：修复 `flutter pub get` 报 “Building with plugins requires symlink support” 导致双击 Debug/构建失败的问题。`setup_windows_dev.ps1` 和 `run_windows.ps1` 现在会检测 Windows Developer Mode；管理员权限下自动启用 symlink 支持，非管理员权限下打开 `ms-settings:developers` 并提示手动启用后重试。

- Windows 调试启动：修复界面闪一下后因 `sqlite3.dll` 缺失崩溃的问题。文件预览缓存索引不再使用 `sqflite_common_ffi` / SQLite FFI，也不在 Flutter 前端维护 JSON 索引；现在通过 Go bridge 写入现有 bbolt `config.db` 的 `preview_cache` bucket，彻底移除 Windows 运行时对系统 SQLite 动态库的依赖。

- 文件预览诊断：为点击预览链路增加 `preview` tag 分段耗时日志，覆盖弹窗打开、预览源加载、`headObject`、cache index bridge 查询、本地缓存文件校验、下载任务创建/复用、缓存索引写入和读取预览 bytes，方便定位 Windows 预览点击卡顿具体发生在哪一步。

- 文件列表交互：修复文件行鼠标移入后长期保持手指指针的问题。`FileListTile` 现在空闲时使用基础箭头，仅在行自身 `_hovered` 时切换为点击手指；删除中或 dimmed 行同时禁用标题点击，避免不可操作状态仍触发预览/打开。

- 日志采集：新增设置页「日志设置」，支持 `Silent` / `Error` / `Info` / `Debug` 四级过滤并持久化到本地偏好。Flutter 侧 `AppLog` 会把当前等级同步给 Go bridge，后端日志也通过统一的 `go/logging` 包过滤；未手动设置时 Debug 构建默认 `Debug`，Release 构建默认 `Silent`。预览耗时诊断降为 `Debug` 级，正式版默认不采集高频诊断日志。

- 设置页缓存管理：将“缓存设置”卡片拆成「缓存目录设置」「缓存占用」「缓存清理」三个明确分区，目录选择/打开、占用刷新、手动清理与自动清理规则各归其位，避免按钮和状态信息混在同一排。

- Windows 构建脚本：修复 Go 1.18+ VCS stamping 在 Git 返回 128 时阻断 bridge 构建的问题。`run_windows.ps1` 现在会把仓库根目录加入当前用户 Git `safe.directory`，并用 `go build -buildvcs=false -buildmode=c-shared ...` 构建本地调试 DLL。

- 应用更新：修复 Windows 下安装包 SHA-256 校验失败后无法删除坏文件的问题。`verifyDownloadedDigest` 之前在文件句柄仍打开时调用 `os.Remove`，Windows 会保留文件导致 `TestVerifyDownloadedDigestMismatchRemovesFile` 失败；现在读取并关闭文件后再删除 mismatch 文件。

- 应用更新：修复 macOS 一键更新报「挂载 DMG 失败：映像数据已损坏」的问题。根因是安装包下载完成后没有任何校验，部分 GitHub 加速镜像会用 HTTP 200 返回截断的内容或 HTML 错误页，被原样写入 `.dmg`，到 `hdiutil attach` 时才暴露为映像损坏。现在下载完成后做两道校验：①比对本地文件大小与 GitHub Release asset 的 `size`，不一致时删除残留文件并报「下载文件大小不匹配……镜像可能返回了截断或错误内容」；②用 GitHub asset 的 `digest`（`sha256:<hex>`）对落盘文件算 SHA-256 全文校验，大小相同但内容被替换的情况也能挡住，不匹配时删除文件并提示「安装包校验和不匹配：下载内容已被损改，请尝试切换镜像或直连 GitHub 重新更新」。缓存命中本地保留的安装包时也会用这一套大小+校验和校验，避免反复复用坏包。镜像预检 HEAD 也增加 `Content-Length` 与 asset 大小的一致性比对，镜像谎报长度时直接提示「镜像不可用」而非继续下载。

- 应用更新：修复一键更新报「下载失败：读取响应失败：stream error: stream ID 1; INTERNAL_ERROR; received from peer」的问题。根因是部分 GitHub 加速镜像在 HTTP/2 上转发大文件时会在中段 reset 流，单次读取错误直接传给用户即终止。现在下载改为重试续传：遇到 `stream error` / `INTERNAL_ERROR` / 连接重置 / 意外 EOF 等可重试错误时，不直接失败，而是按已落盘字节数用 HTTP Range 续传重试，最多 5 次（含退避）；HTTP 状态码、写入磁盘失败等不可重试错误仍立即返回。撤回此前强制 HTTP/1.1 的尝试，因为 `gh-proxy.com` 会在该路径下返回 HTTP/2 二进制帧，导致 Go 报 `malformed HTTP response`。

- 构建：`make push` 在最新 `v*` 语义化标签上递增版本（默认 patch）、创建附注标签并推送当前分支与标签以触发 Release CI；脚本 `scripts/bump_and_push_tag.sh`，支持 `BUMP=minor|major`、`FORCE=1`。
- 构建：`make push` 的 patch 递增在 patch 为 9 时进位到 minor（`v1.1.9`→`v1.2.0`），minor 为 9 时再进位到 major（`v1.9.9`→`v2.0.0`）。

- 设置页：网络代理改为下拉选择（跟随系统 / 直连 / 自定义）；切换跟随系统或直连后自动保存，仅自定义时显示代理表单与「保存代理设置」按钮。

- 设置页：取消右侧滚动时左侧锚点高亮自动跟随（原按全局 Y 距离计算易不准）；左侧高亮仅在点击锚点跳转时更新，滚动不再改写选中项。

- 应用更新：GitHub 下载加速镜像改为下拉选择（直连 / gh-proxy / ghfast / 自定义）；仅选「自定义」时显示地址输入框。测试镜像可用性进行中禁止切换镜像与编辑自定义地址。

- 应用更新：一键更新进行中（含等待上传/下载、下载、安装）主按钮改为可点击的「取消更新」，不再显示不可点的「更新中...」；此期间隐藏「检测更新」按钮。

- 应用更新：一键更新前若传输队列中存在进行中的上传或下载任务，会先等待这些任务完成再启动更新下载，避免与文件传输争抢带宽或中断用户传输。

- 应用更新：安装包写入设置/工作路径下的 `cache/app_updates/`（不再用系统临时目录）；完整包且大小与 Release asset 一致时直接命中本地缓存跳过下载。支持 HTTP Range 断点续传，中断后再次更新可从已有部分文件继续。

- 应用更新：传输队列将 `app_update` 显示为独立「应用更新」任务（不再误显示为上传）。修复 `TransferQueue._kindFromWire` 未处理 Go 快照 `type: app_update` 而默认成上传；新增 `TransferKind.appUpdate`、传输页类型筛选与任务行图标/等待文案。

- 应用更新：修复 macOS 一键更新完成后弹出前台 shell 进程且旧进程未正常退出的问题。根因是 `relaunchApp` 用 `open -n .../Contents/MacOS/云卷` 启动可执行文件二进制而非 `.app` bundle，绕过了 LaunchServices 的窗口/激活生命周期。现改为 `open -n /Applications/云卷.app`，新进程作为正常 app 启动；旧进程仍走 `os.Exit(0)` 退出全进程。

- 应用更新：修复每次启动镜像配置都显示为“直连”的问题。根因是 `SettingsUpdateMirrorField` 在 `_loadMirrorConfig` 异步完成前用空前缀初始化 `_mode`，`initialConfig` 到达后没有 `didUpdateWidget` 重新解析。新增 `didUpdateWidget`：当父级传入的 `mirrorPrefix` 变化时重新推断 `_mode` 并清空探测结果。SharedPreferences 中实际已正确保存 `flutter.update.mirror_prefix`。

- 应用更新：修复一键更新在传输页显示为“上传”的空任务（`app_update` 类型现映射为下载），并在使用镜像下载前做 HEAD 预检，镜像返回非 2xx 时直接给出“镜像不可用”提示而非一直停在 0B。镜像配置区新增“测试镜像可用性”按钮，对当前选中镜像包裹真实 GitHub Release asset URL 做 HEAD 探测，直观显示镜像是否支持大文件下载；新增单元测试验证 mirrorPrefix 持久化读写与 `app_update` kind 映射。

- 应用更新：降低“检测更新”与一键下载因超时失败的概率。GitHub Release 版本检查单次超时由 10 秒放宽至 30 秒，并对网络类错误自动重试最多 3 次；Go 侧安装包下载 HTTP 客户端整包超时由 120 秒放宽至 7200 秒，避免大包或慢速镜像下载中途被切断。

- 应用更新：一键更新进行中时，在更新卡片按钮区直接显示“取消更新”。点击后会调用传输队列/bridge 的 `cancel_transfer` 终止 Go 侧 `app_update` 任务，取消正在进行的 HTTP 下载并恢复更新卡片状态，无需跳转到“传输”页。

- 应用更新：修复 macOS 上 `unsupported bridge method "install_app"` 错误。根因是 macOS app bundle 可能同时存在两个 bridge dylib 副本——一个在 `Contents/MacOS/`（早期手动构建或调试运行遗留），一个在 `Contents/Frameworks/`（`make build-macos` 写入）。`_findBundledLibraryPath` 的查找顺序里 `MacOS/` 排在 `Frameworks/` 之前，导致 Dart FFI 加载的是旧 dylib，没有 `install_app` 方法。现在改为 `Frameworks/` 优先于 `MacOS/`，并在 `build-macos` 目标里拷贝前 `rm -f` 清除 `Contents/MacOS/` 下可能残留的旧 dylib。

- 应用更新：macOS/Windows/Linux 三平台更新全流程从 Dart 迁移到 Go bridge。Dart 不再执行任何平台逻辑（无 `Process.run`/`hdiutil`/`cp`/`xattr`/`HttpClient`），仅通过 `TransferQueue` 轮询进度。Go bridge 新增 `install_app` 方法，后台 goroutine 完成下载（带镜像/代理）+ 安装 + 重启，进度实时上报 `transferMonitor`。修复之前 `hdiutil attach` 输出因 locale 差异解析失败导致挂载点定位错误的根因（改用 `-plist` 输出解析 + `/Volumes` 扫描兜底）。设置页 `SettingsUpdateSection` 改为监听 `TransferQueue.instance` 获取实时进度。`RemoteStorageApi` 的 `installApp` 方法拆入独立 part 文件控制代码行数。

- 应用更新：修复一键更新在 macOS 上因临时目录缺失导致 `PathNotFoundException` 的问题。`getTemporaryDirectory()` 在 macOS 上常返回 `~/Library/Caches/<bundle-id>/`，但该目录可能尚未创建，`File.openWrite()` 不会自动建父目录，导致下载阶段即以 "No such file or directory" 失败。现在下载前显式 `create(recursive: true)` 一个 `app_updates` 子目录并校验写入结果；安装阶段若安装包已被清理则给出明确提示而非 `hdiutil` 报错。同时补上 HTTP client 的释放。

- 账号管理：新增/编辑账号在桌面端改为独立子窗口（`desktop_multi_window`），不再使用 ShadDialog 拟态框；子窗口自带 bridge 连接和表单保存，保存成功后通过 method channel 通知主窗口刷新列表。Web 端或无法创建子窗口时仍回退到拟态框。

- 应用更新：修复三个问题。① 版本检查（GitHub Releases API）走镜像会返回 403，现在 API 调用永远直连 GitHub，镜像只用于安装包下载；② 一键更新在 ARM 版应用上误下 universal 包，改为优先匹配当前构建架构（后端 `get_build_info` 注入 `buildArch`，Dart 侧做兜底），找不到再回退 universal；③ 下载进度在未知总大小时停在 0%，现在显示已下载字节数与连续滚动进度条。

- 设置页：改为左侧锚点目录 + 右侧完整滚动页布局。左侧按「通用 / Windows / 关于」分组列出应用更新、网络代理、外观、下载设置、缓存设置、显示设置、同步设置、回收站、Web 端 WebDAV 凭据、账号重置、配置管理等锚点，点击会滚动定位到对应卡片；滚动右侧内容时左侧高亮会跟随当前区块。左侧分组项支持 hover 高亮反馈（`_SettingsGroupTile` StatefulWidget）。

- 配置存储：从 TOML 配置文件迁移到 bbolt 单文件数据库（`~/.cloud-volume/config.db`）。所有账号配置、代理设置统一存储在 bbolt 的 JSON bucket 中，不再使用分散的 TOML 文件。首次启动时自动从旧的 `profiles/*.toml` 和 `config.toml` 迁移到 bbolt，迁移完成后删除旧文件。从根本上避免了 `saveConfig` 整体覆盖导致丢账号的问题。

- 网络代理：设置页新增「网络代理」配置区，支持三种代理模式：跟随系统（读取 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量，默认）、直连（忽略所有代理）、自定义代理。自定义代理支持 HTTP 和 SOCKS5 两种代理类型，可配置代理地址、端口、账号和密码（账号密码可选）。代理设置影响应用所有网络请求（S3、WebDAV、百度网盘、GitHub 更新检查）。Go 端 S3 SDK（AWS SDK）、WebDAV HTTP 客户端、百度网盘 SDK 和 MinIO 客户端均已接入代理传输；Dart 端 GitHub API 和下载请求也使用代理感知的 HTTP 客户端。
- 应用更新：GitHub 下载加速镜像改为选择模式（直连 / gh-proxy / ghfast / 自定义），选择「自定义」时才显示地址输入框，减少误操作。
- 应用更新：GitHub 更新检查和一键更新下载支持配置加速镜像（如 `gh-proxy.com`、`ghfast.top`），避免因网络问题导致更新失败。镜像地址可在设置页「应用更新」区域选择或自定义。

- 应用更新：设置页“检测更新”发现新版本后，桌面端可直接点击“一键更新”在应用内自动下载安装包、替换旧版本并自动重启，不再需要手动卸载重装或执行命令行命令。macOS 自动从 DMG 提取并替换 `/Applications/云卷.app`，同时移除隔离属性（不再提示“已损坏”）；Windows 静默运行 Inno Setup 安装程序；Linux 替换 AppImage 或解压 tar.gz。Web 端仍跳转 GitHub 下载页。
- 文件管理：修复 macOS 上从访达复制文件后 Cmd+V 粘贴上传失效。Flutter macOS 引擎将 Cmd+V 等 key equivalent 发给 FlutterView.keyDown:（普通 NSView），其 interpretKeyEvents: 把事件交给 TSM 输入上下文后静默吞掉，永远到不了引擎键盘管理器和 Flutter Shortcuts。改为在 NSWindow.performKeyEquivalent 拦截 Cmd+V/C，通过 method channel 直接通知 Dart 侧读剪贴板上传。同时修复 Cmd+C 从远端复制选中文件到系统剪贴板。
- 文件预览：本地拖拽上传成功后，立即把本地副本登记进预览缓存，双击打开刚上传的文件直接命中缓存，不再重复下载；缓存写入失败不阻断上传成功。
- 文件同步：「打开同步目录」修复 build 阶段 setState 报错；进入文件管理后正确打开桶与前缀。
- 同步配置：新增「打开本地目录」「打开同步目录」；远端跳转文件管理对应桶与前缀。
- 文件管理：存储桶列表移除「类型」列；窄窗口自动隐藏来源/操作列，桶名称占用更多宽度。
- 桌面端：新增 `write_flutter_log` bridge 方法与 `AppLog`，Flutter 日志可写入与 Go 相同的 bridge 日志文件。
- 同步配置编辑器：在「同步策略」直接点保存时校验本地/远端目录，提示并跳回「同步两端」，避免空指针无响应。
- 文件同步：本地与远端同名同大小的 0 字节文件不再反复同步；首次缺失一侧仍会正常拉取/上传。
- 同步配置编辑器：步骤「同步两端 / 同步策略」改为可点击选项卡，可自由切换查看；保存时仍校验必填项。
- 文件同步：「立即同步」不再显示操作数量；修复远端列表时间为空时误判变更导致多余下载、刷新本地修改时间。
- 文件同步页：移除底部「同步任务」列表；每条同步配置卡片内显示当前最新进行中的同步任务，完整列表在「传输」页。

- 文件同步：修复误删本地目录（目录 index 与仅扫描文件的本地快照不一致）；「立即同步」提示改为说明调度操作数。
- 文件同步：远端空目录也会同步到本地（`ensure_local_dir` / `sync_mkdir`），不再要求目录内必须有文件才出现本地文件夹。
- 文件同步：修复远端目录仅扫描一层导致子目录文件不会自动下载的问题（双向/下载模式在本地空目录时无法拉取远端树）。
- 远程目录选择器：不可选文件行标题与大小文字置灰；压缩包等多色 SVG 图标改用灰度矩阵处理，避免仍显示彩色。

- 远程目录选择器：目录下列出文件（灰色、不可点击）；新增「显示隐藏文件」开关，默认隐藏以 `.` 开头的条目。
- 桌面子窗口模态体验：打开同步配置/远端目录子窗口时父窗口显示灰色遮罩并拦截点击；子窗口 `setMovable(false)` 且标题栏不再 `DragToMoveArea`，更接近 ShadDialog 行为。
- 远程目录选择器改为独立子窗口：同步配置里「选择远端目录」在桌面端打开 `desktop_multi_window` 窗口（720×560），不再嵌套 ShadDialog；新增 `showDesktopOverlayOrDialog` 统一桌面子窗口 / Web 拟态框回退。
- 同步配置编辑器远端目录改为可视化选择：新增文件管理式远程目录选择器（`RemoteDirectoryPickerDialog`），用户像在文件管理页一样浏览桶列表→进入目录→选当前目录，支持面包屑导航和新建目录。不再需要手动输入桶名和目录前缀，关联账号自动绑定。编辑器保留两步向导结构（同步两端 → 同步策略）。

- 同步配置编辑器改为独立子窗口：创建/编辑同步配置不再使用 ShadDialog 拟态框（空间太小），改为 `desktop_multi_window` 独立 OS 窗口（640x660），自带 bridge 连接和桶列表加载。Web 端降级回退到拟态框。模式与文件预览窗口（`FilePreviewWindowApp`）一致。

- 文件同步配置入口迁移：将同步配置的新增、编辑、删除、启停操作从「系统设置 → 文件同步」子 Tab 移至「文件同步任务」页面，使其成为同步配置的唯一管理入口。设置页不再包含文件同步 Tab，删除了 `settings_file_sync_section.dart`；文件同步页新增「新建配置」按钮和完整的配置卡片操作，CRUD 逻辑拆分到 `file_sync_tasks_page_actions.dart`。

- 修复 `pubspec.yaml` 把 Dart SDK 约束钉死在 `^3.12.0` 导致 `make run` 在 Flutter 3.41（Dart 3.11.4）等较旧但可用的 stable 通道直接失败的问题：约束改为 `>=3.11.0 <4.0.0`，clone 后无需升级 Flutter 即可直接 `make run`。

- 新增文件同步功能：可指定本地目录定期同步到远端桶目录，支持仅上传、仅下载和双向同步。双向同步通过本地索引加三方比对（本地快照 / 远端列表 / 持久化索引）识别新增、修改、删除与重命名操作，冲突按较新、本地优先、远端优先或跳过策略处理；正在写入的热数据会等到静默指定秒数后才纳入同步，避免频繁操作远端。同步任务复用现有任务队列，新增 sync_upload / sync_download / sync_delete / sync_rename 任务类型。同步配置在文件同步页面统一管理（新增、编辑、删除、启停、立即同步），页面同时展示同步进度与状态。同步索引采用 bbolt KV 存储，按 key 单条读写，内存占用恒定且不随文件数量增长。

- 修复打开预览的文件在远端已被删除（404/NoSuchKey）时，预览拟态框仍显示"外部应用打开 / 另存为 / 下载"按钮，且点击下载报错后弹框按钮仍显示"后台运行"的问题。现在下载/另存为/外部打开返回 404 时，弹框按钮立即收敛为"关闭"，并在错误出现的瞬间就触发当前目录的元数据刷新，关闭弹窗时再兜一次，确保已删除的条目无论用户后续怎么操作都会从列表中消失。

- 修复 Windows Cloud Files 缓存读取路径的一个回归：`readCachedRange` 在清理 sync-root 占位标记后总是重新走 `ensureLocalFile`，当缓存元数据已命中但远端 HEAD/下载失败（例如远端对象已被删除）时会直接返回 `file does not exist`，导致占位符水合失败。现在会先检查缓存元数据与本地缓存文件，命中时直接从本地缓存按范围读取，避免不必要的远端往返；同时把本地范围读取逻辑抽取为 `readLocalRange` 复用。

- 修复 Windows 下 Alt+F4 / 任务栏关闭不会弹出“隐藏到托盘 / 退出云卷”确认框、直接退出的体验问题：原生窗口现在在托盘激活时拦截 `WM_CLOSE` 并通过新增的 `requestClose` 通道方法回调到 Flutter，统一走应用内关闭按钮的确认流程；新增 `WindowControls.shouldConfirmClose` / `registerCloseRequestHandler` 配套 API，`DesktopWindowControls` 在生命周期内自动接管 OS 关闭请求。
- 新增 Windows 单实例保护：`main.cpp` 通过命名互斥量 `CloudVolume.Singleton` 阻止第二次启动再开一个进程和重复的托盘图标。
- 补充 Windows 关机/注销时的优雅退出：`Win32Window` 现在显式响应 `WM_QUERYENDSESSION` / `WM_ENDSESSION`，会话结束时强制销毁窗口，让 Flutter engine 与 bridge 资源有机会正常释放，而不是被 OS 直接杀掉。
- 修复托盘右键菜单可能弹出两次或在按下时弹出的问题：移除 `WM_RBUTTONUP` / `WM_RBUTTONDOWN` 的手动处理，`NOTIFYICON_VERSION_4` 下完全依赖 shell 投递的 `WM_CONTEXTMENU`。
- 修复 Windows 上用“外部应用打开”打开含空格或特殊字符路径时 `cmd /c start` 解析失败的问题：路径现在用引号包裹。
- 修复 `openMountPath` 在 `ShellExecuteW` 失败时把 `syscall.Errno` 当作“真实错误”的误导性分支（实际只在 errno 非成功值时才透传，否则回退到返回值码），错误信息现在同时包含 result 值。
- 扩大 `CleanupStaleWindowsProcesses` 的清理范围：从只匹配 `build/windows/x64/runner` 改为 glob 匹配 `build/windows/*/runner`，覆盖 arm64 等其它架构的本地 debug runner；并把 `Stop-Process` 改为 `SilentlyContinue`，单个进程（已提升权限或已退出）失败不再中止整轮清理，计数改为按真实退出结果统计。
- 修正 `AGENTS.md` 中 Windows 启动命令损坏为 `.un_windows.ps1` 的笔误，恢复为 `.\run_windows.ps1 -Build`。
- 修复 Windows Cloud Files watcher 的一个偶发竞态：当某目录的 placeholder 写回忽略窗口未过期时，`watchPlaceholderDirectories`（Explorer 显式拉取该目录时触发）虽然重新挂了 fsnotify，但目录本身的 `shouldIgnore` 仍返回 true，导致打开后的嵌套复制写入被丢弃，`TestFetchPlaceholderCallbackRearmsOpenedDirectoryWatch` 在并发压力下偶发失败。现在显式拉取目录时会调用 `clearIgnore` 清掉该目录的占位忽略窗口，让随后的真实写入进入队列。
- 把 `TestWindowsSyncWatcherCloseReturnsDuringHarvest` 的关闭等待超时从 3 秒放宽到 10 秒，缓解高负载机器上 watcher 关闭与 harvest goroutine 收尾偶发超过 3 秒导致的偶发失败（关闭逻辑本身不变）。
- 整理 `windows_installer.iss` 的签名配置：当只传 `SignTool`（视为完整 signtool 命令行）时不再强行依赖 PFX 变量，澄清三种签名输入（完整命令行 / PFX 对 / 主题名）的互斥关系。


- 修复 Windows 下隐藏到托盘后再点击托盘无法恢复主窗口、关闭应用重新打开也只剩托盘不显示主界面的问题：根因是隐藏用 `SW_HIDE`，而恢复路径用的是 `SW_RESTORE`/`SW_MAXIMIZE`，对纯隐藏的窗口是 no-op，主窗口永远不会再被显示出来。现在恢复托盘和启动时统一改走 `SW_SHOWNORMAL`/`SW_SHOWMAXIMIZED`，并在 `OnCreate` 里直接显式显示主窗口作为安全网，避免首帧回调未触发时应用启动到只剩托盘的状态；隐藏前会记住最大化状态，恢复后窗口形状保持一致。

- 修复挂载只能挂一个桶的问题：Go 后端 `mount/manager` 从单 `session` 指针改为按 bucket 索引的 `sessions` map，挂载新桶时不再自动卸载旧桶；Flutter 端同步移除 `_applyMountStatus` 中强制把其他桶标记为已卸载的逻辑，以及 `_refreshVisibleMountStatusesOnce` 中只刷新单个桶的限制。现在支持同时挂载多个桶，每个桶的挂载状态独立维护。
- 修复同时挂载多个桶后点击前一个桶提示 `bucket is not mounted` 的问题：Windows 后端 `CleanupStale` 之前会清理全部桶的 Cloud Files 和 WebDAV 挂载，现在改为仅清理当前桶对应的挂载；`cleanupManagedWindowsWebDAVMountForBucket` 会按桶名精确匹配 `net use` 映射，避免污染其它桶的驱动器。
- 修复远端文件已删除但本地元数据缓存仍存在时，读取文件卡住或报错不明确的问题：挂载层在 stat 或 range-read 返回 404 时会立即清除对应的元数据缓存条目，避免后续访问继续命中幽灵缓存；UI 刷新按钮现在会同步清掉 Go 后端挂载层的目录缓存（新增 `forceRefresh` 桥接参数），确保点刷新后真正从远端拉最新列表；`describeBridgeError` 也补充了 `NoSuchKey` / `NotFound` / 404 等错误的中文提示，不再显示原始 Go 错误字符串。
- 任务队列页现在支持清理历史记录：已完成 / 失败 / 已取消的任务行右键/行内新增“从记录移除”按钮；多选时批量操作区会显示“移除记录 N”；标题栏新增“清空已完成”一键清掉全部已结束记录（带二次确认）。运行中或等待中的任务不会被删除，目录上传的子任务由父任务托管也不会被单独移除；移除记录只清理本地历史，不影响实际远端文件。
- 修复上传超大文件（如 30 GB）被父 context 超时一刀切全部杀掉的问题：每个分块现在都用 `context.WithoutCancel` 派生出独立超时的子 context，单个分块的 timeout 不再传染到其它分块；同时给每个分块加上最多 10 次自动重试（首次 0s、第二次 1s、第三次 2s…依次类推的线性退避），覆盖 5xx、`RequestTimeout`、`SlowDown`/`Throttling`、连接重置、`EOF`/`UnexpectedEOF` 等常见瞬态错误，用户主动取消或非瞬态错误（如 `AccessDenied`、`InvalidPart`）不会重试。
- 修复上传失败后文件列表不刷新、点击“刷新”也不重新请求的问题：刷新流程现在会先清掉内存中的对象列表缓存并清空当前列表显示，再向后端重新请求；同时上传成功/失败都会触发当前目录重载，失败时也能立即看到部分上传的对象。
- 设置页“缓存设置”卡片现在支持完整的缓存管理：显示当前缓存占用（人类可读，含文件数），可“选择目录 / 恢复默认 / 打开缓存目录（仅桌面端）/ 刷新统计 / 按规则清理 / 清空缓存”；新增“自动清理缓存”开关、“最大占用 (MB, 0=不限)”与“最大保留天数 (0=不限)”三项规则配置。规则按“先按年龄删超期文件，再按 mtime 从最旧到最新删除直到总大小满足上限”的顺序执行，只清理缓存目录内容，不影响账号配置、profile 与 runtime 日志。桌面端开启自动清理后会在启动时和每小时后台巡检一次；Web 端不提供“打开目录”按钮（浏览器无此能力），但同样支持统计与清理。
- 设置页“通用设置”底部新增“账号重置”入口：确认后一键清空所有已保存的账号、密钥与 WebDAV 凭据（包含旧版 `~/.remote-storage` 与旧 Windows 安装目录下的遗留配置），并回到首次启动初始化页。已挂载桶与缓存目录不受影响，可重新配置后继续使用；Web 端在重置的同时会清掉当前会话 Cookie，避免对空配置继续保留登录态。
- 设置页“通用设置”底部新增“配置管理”卡片，把原来跨 tab 显示的 `重新配置`、`刷新状态`、`退出登录` 统一收进通用设置内部，避免 Windows 设置页也重复出现这些通用操作。
- 修复 Windows 下 `flutter run -d windows` 运行时缓存管理报 `unsupported bridge method get_cache_stats` 的问题：原因是 `windows/CMakeLists.txt` 中的 `install` 命令限制了 `CONFIGURATIONS Profile;Release`，导致 Debug 配置（`flutter run` 默认）不会把最新编译的 `remote_storage_bridge.dll` 复制到 runner 目录，runner 加载的是旧版本 DLL。已移除该限制，现在 Debug 配置也会正确复制最新 bridge DLL。
- Windows 设置页暂时隐藏“Windows 挂载模式”卡片，不再允许用户从界面切换模式，保留底层逻辑供后续统一打开。
- Windows 默认配置、缓存与运行时目录现在统一改回用户主目录下的 `~/.cloud-volume`（与 macOS/Linux 一致），不再写到安装目录下与 `cloud-volume.exe` 同级的位置；这样在 `C:\Program Files\Cloud Volume` 这类需要管理员权限的安装目录下首次启动时不会再因为写不进 `config.toml` / `runtime/` / `cache/` 而失败。升级启动时如果主目录下还没有配置，也会继续从安装目录下旧的 `config.toml` 迁移过来。
- WebDAV 新建目录现在会在 bridge 日志里记录 `[webdav/mkdir]` 开始、`MKCOL` 响应、`405` 后目录存在性反查以及最终错误，方便排查目录创建失败但界面只看到错误提示的情况。
- 修复 WebDAV 新建目录时把 `MKCOL 405 Method Not Allowed` 一律当作成功的问题；现在只有反查确认目标目录已经存在时才视为幂等成功，否则会把真实的创建失败反馈到界面。
- 任务队列现在会同步显示前台进度弹框中的上传/下载任务，侧边栏“对象传输”不再在弹框上传或下载时显示“暂无任务”；目录上传和目录下载也会额外记录每个文件的子任务，失败的单文件上传/下载可直接从任务队列单独重试。
- 账号管理页“新增账号 / 编辑账号”弹框现在每个输入框上方都会显示字段名（名称、网关地址、区域、访问密钥 ID 等），输入后也能直观看到当前正在填写哪一项；URL、Region、Access Key、WebDAV 用户名和百度授权码等技术字段也会关闭智能标点/自动纠错，并把常见全角标点规范为半角，避免中文输入法把 `https://` 这类连接地址打坏。
- 文件预览弹框里的“外部应用打开 / 另存为 / 下载”现在会直接在预览区域切换为下载进度；外部应用打开会在下载完成后自动打开本地文件并关闭弹框，下载和另存为则显示完成状态。文件列表右键下载和多选下载也会弹出统一下载进度框，不再静默进入后台任务；右键下载会先弹出统一拟态进度框，再继续选择本地保存路径；目录下载在展开目录阶段失败时也会把错误显示在下载任务行里，并在扫描后展示总文件数和总字节数。百度网盘下载和文件信息读取现在也避开 SDK 会把 `hit frequency limit` 吞成 `file not found` 的游标查找，改用带退避重试的路径查找；列表结果会在后端缓存 fsid，后续下载、预览和范围读取会优先用 fsid 获取下载地址，避免每个文件下载前再次 list；下载到本地路径时会先复用已有文件内容缓存，目录递归下载中的子文件也会优先从缓存复制，已经浏览过的目录层级会复用页面对象列表缓存。
- 文件管理页现在会按账号、bucket、目录前缀和分页 token 缓存对象列表；普通目录来回切换会直接复用已加载页面，只有右键“刷新”、错误页重试或写操作完成后才会绕过并更新缓存。百度网盘目录列表遇到 SDK 返回的 `hit frequency limit` 也会按既有退避策略重试，并会过滤 `listall` 返回的当前目录自身条目，避免同名目录看起来能选中但递归下载时报 `file not found`。
- 文件管理页的加载态现在会显示中文等待文案；百度网盘目录列表如果等待超过短暂延迟，会提示可能触发频率限制并正在自动重试，不再只显示一个空转圈。
- 设置页“通用设置”顶部现在新增更新检查区，可检测 GitHub 最新 Release，并直接跳转到 GitHub 下载更新。
- 文件管理页面包屑现在更接近 Windows 文件管理器的折叠逻辑：空间不足时优先把更早层级收入省略菜单，保留最近几级目录完整显示。
- 批量上传/删除进度弹框现在只保留“后台运行”作为未完成任务的关闭入口，并把“取消上传/取消删除”按钮改为警告样式，避免和后台继续执行混淆。
- 文件管理页单个文件夹右键菜单现在会显示“下载”，桌面端会递归展开目录并按原相对路径下载到本地；多选批量下载也不再忽略选中的文件夹。
- 百度网盘文件夹上传现在使用保守小并发上传文件，并在上游返回 403 限流响应或单个文件上传失败时自动 sleep 后重试，避免 RPM 限制把整条目录上传链路直接打断；上传失败弹框也会显示具体失败原因和文件路径。
- 修复批量删除完成后进度弹框的顶部进度条仍以不确定态动画转动的问题；无字节总量的删除任务完成后现在会显示 100% 完成进度。
- 文件管理页批量删除现在会弹出统一拟态进度框，展示每个删除任务的状态，并可关闭弹框切到后台继续执行。
- 百度网盘目录创建现在会先做幂等检查并缓存已确认目录，避免重复创建已存在目录时被上游自动改名，同时保留文件夹拖拽上传的并发能力。
- 百度网盘上传现在会关闭 `xpan` SDK 默认的每接口 10 次/分钟限流，避免 4MB 分片上传在文件或目录拖拽上传时被 SDK 内部节流卡住。
- 文件管理页进入多选状态后，点击文件或目录现在都会切换选择状态，不再误打开文件或进入子目录。
- 文件管理页鼠标圈选现在会与已有多选状态做切换合并：框内未选对象会加入，框内已选对象会取消，框外选择会保留，拖拽过程中滚动列表也不会打断本次圈选。
- Release 文案里的国内加速下载区现在会按当前 tag 和实际构建产物生成表格，原始 GitHub、`gh-proxy`、`ghfast` 链接都可直接点击，不再保留旧版 `v1.0.0` 示例链接。
- 文件管理页桌面端拖拽/粘贴上传现在支持本地文件夹：前端会立即显示统一上传拟态框，Go bridge 在后台扫描目录树、创建远端目录并按相对路径上传文件，同时回传已发现/已上传文件数量并支持从弹框提前取消，避免大目录在 Flutter 侧展开任务时卡住界面。
- 文件夹上传现在会先完成本地目录扫描并一次性拿到总文件数与总字节数，再进入上传阶段；中途取消、失败或完成后都会刷新当前文件列表，空白区右键菜单也新增“刷新”入口，方便查看已部分上传的对象。
- 文件夹上传弹框现在区分目录总进度和当前文件进度：顶部汇总卡显示整个目录的字节与文件数量进度，任务行显示当前正在上传的文件路径、字节进度和独立进度条。
- 文件夹上传现在使用 Go 后端 4 路有界并发上传文件；上传弹框去掉单任务场景下重复的“1 个任务”标签，并把速度合并到目录总进度栏，避免顶部与任务行重复显示。
- 文件管理页右键菜单现在区分空白区、单对象和多选对象：多选右键不再和背景菜单抢事件，空白点击会取消当前选择，空白区也可直接新建目录或上传文件。
- 文件管理页现在支持桌面端鼠标圈选：在文件列表或网格中按住左键拖出选框即可批量选中当前可见对象，继续复用现有多选、批量下载和批量删除链路。
- 修复百度网盘桌面挂载在 macOS 上长时间卡住的问题：挂载层现在把目录预取改成后端能力开关，百度网盘默认禁用目录 `prefetch`，避免挂载后为了预览子目录持续触发受限速的上游 OpenAPI 请求。
- 设置页现在支持显式控制挂载元数据缓存：默认启用 1 分钟缓存，也可以直接关闭；关闭后挂载目录浏览和文件元数据读取会始终直接请求远端，不再让用户理解内部 `-1` 之类的关闭语义。
- 设置页里的回收站自动清理也改成显式开关 + 保留天数输入：关闭时只保留回收站内容，开启后按保留天数后台清理；界面不再暴露 `-1` 或“非负数表示开启”这类不直观规则。
- 修复 S3 桶对象列表与 `headObject` 返回的 `lastModified` 时间展示：后端现在会把 S3 返回的 UTC 时间统一转换为当前本地时区后再返回给 Flutter，避免文件列表里直接显示未校正的 UTC 时间。
- 修复文件管理页对百度网盘挂载的前端误拦截：在挂载链路已经抽象为多后端通用接口后，百度网盘不再被 `supportsMounts` 和“暂不支持桌面挂载”的旧 UI 判断提前拦住。
- 账号管理与文件管理首页现在改成真正的多账号共存模型：新增账号后不再需要单独点击“连接”或切换当前账号，文件管理首页会直接聚合展示所有账号下的 bucket / 根目录，并在“来源”列标出所属账号与存储类型。
- 新增百度网盘 OpenAPI 上游：账号管理与首次初始化现在支持“百度网盘”类型，桌面端会按百度要求使用 `oob` 模式打开浏览器授权页，用户把网页显示的授权码手动粘贴回应用后完成 OAuth 换 token；后端通过 `github.com/lfhy/xpan` 接入百度文件浏览、下载、上传、复制、移动、重命名、删除与挂载链路，并按百度限制把上传内容先写到 `/apps/网盘demo/` 再移动到最终目标路径；分享管理仍暂不在百度账号下开放。
- 挂载层现在把远端列表、范围读取、建目录、移动、删除、下载和延迟写回都收敛到统一的 storage backend 能力接口，不再在 mount 内部直接绑死 S3 远端操作；因此 S3、WebDAV 和百度网盘可以共用同一套本地优先挂载链路，只有 Linux 的分段预上传仍按后端能力做可选优化。
- 文件管理页的上传现在会先弹出统一的拟态进度框，拖拽上传、粘贴上传和按钮上传都会显示当前任务列表与进度摘要，并支持直接关闭弹框或切到后台继续上传。
- 文件管理首页的桶列表现在新增“桶设置/配置”入口，可为每个桶单独设置只读、是否启用回收站，以及桶级回收站目录覆盖；关闭回收站的桶会同步隐藏文件管理里的“打开回收站”入口。
- 桶级策略现在同时作用于桌面 bridge、Web API、S3 backend、WebDAV backend 与挂载链路：只读桶会拒绝上传、新建、删除、改名、移动、恢复回收站与清空回收站等写操作；S3 删除会按桶策略决定软删或硬删。
- WebDAV 现在完整支持桶级回收站的 list/restore/delete/clear，并复用与 S3 一致的回收站元数据模型；WebDAV 默认关闭回收站，启用后可把回收站目录改到可写子目录，例如 `20134-image/.trash`。
- 左下角传输历史浮层现在会延迟收起，并允许鼠标移动到浮层内继续操作，避免刚移过去就消失。
- macOS 关闭按钮与原生 close 事件现在统一弹出“退出云卷 / 隐藏到托盘 / 取消”确认，不再绕过确认直接最小化窗口。
- WebDAV 目录权限探测现在会把 PROPFIND / OPTIONS 的状态码、Allow 头、解析到的 privilege 和最终判定写入 bridge 日志，便于排查应为只读却被放行的目录。
- WebDAV 目录权限探测在 ACL 缺失时会继续按当前目录的 OPTIONS Allow 判断；只有 Allow 明确只暴露只读方法集时才会判定为只读，像 `LOCK/COPY/MOVE/PROPPATCH` 这类未列出 `PUT` 的变更能力也不再被误判成只读。
- WebDAV 文件管理会按当前目录探测写入权限；明确只读的目录会禁用新建目录、上传、拖拽上传和粘贴上传，并在后端写入入口同步拦截；根目录只读但子目录可写时不再把只读状态错误继承到子目录。
- WebDAV 文件列表现在会像 S3 一样把目录排在顶部，再按名称排序，避免受服务端 PROPFIND 原始返回顺序影响而把文件夹夹在文件中间。
- 图片预览现在默认先弹出与其他格式一致的应用内预览框，并在框内显示加载状态；预览弹框统一提供“外部应用打开”入口，不再依赖独立大图窗口。
- 文件管理首页的桶操作现在收敛为主按钮 `挂载/卸载` 加 `更多` 菜单；`回收站/桶设置/打开挂载目录/WebDAV 地址` 统一复用桶项右键菜单内容，且未启用回收站的桶不再显示“打开回收站”入口。
- 新增/编辑账号与首次初始化配置现在统一调整字段语义：S3 账号只显示 `名称`，WebDAV 账号同时显示 `名称` 和 `映射桶名称`，其中 WebDAV 的映射桶名称默认跟随名称联动，除非用户手动改写。
- 修复 WebDAV 文件点击图片预览时 `head_object` 把 Depth 0 目标自身过滤掉，导致已列出的文件仍提示 `file does not exist` 的问题。
- 桌面端图片预览现在统一走应用内预览弹框并支持缩放查看；图片以及其他暂不支持内嵌预览的格式都可以直接切到系统默认应用打开。
- 初始化配置与账号新增/编辑现在可以配置映射桶名称；WebDAV 账号不再固定显示为 `WebDAV`，未填写时默认使用账号名称。
- 文件管理对象列表现在支持拖入本地文件上传、在列表中粘贴系统剪贴板里的本地文件上传，以及复制选中的远端文件后粘贴到本地目录。
- 文件管理列表、网格与传输任务行现在统一使用灰色 hover/pressed 背景，避免普通悬停状态被品牌色高亮。
- 修复 WebDAV 账号在文件管理分页列表中因为桥接层传入空请求上下文而报 `net/http: nil Context` 的问题。
- 文件列表默认点击现在会打开预览窗口；图片可直接在窗口中查看，不支持内嵌预览的 PDF、视频、Word 和其他文件会提示下载查看，并提供取消、另存为、下载操作。
- 初始化配置页现在改为两步添加存储账号：无配置文件时先选择 S3 对象存储或 WebDAV，再进入对应账号表单，点击确认添加后才写入默认配置。
- 文件管理页现在只会持续刷新已挂载或正在挂载的 bucket 状态，未挂载桶不会再每 4 秒触发一次 `get_bucket_mount_status`；桥接层也不再为普通状态查询刷 info 日志。
- 账号管理新增/编辑 S3 账号时现在提供路径风格访问高级选项，和初始化配置页保持一致，便于配置 MinIO 和其他 S3 兼容对象存储。
- 账号管理在新增、更新或切换账号后会保留当前侧边栏页面，不再因为刷新配置状态而跳回文件管理页。
- 账号管理删除默认账号时现在会同步清理当前默认配置与旧 Remote Storage 配置源；升级迁移成功后也会删除旧配置源，避免已删除账号在刷新或重启后被旧配置自动恢复。
- 全局回收站与桶级回收站列表现在显示独立操作列，可直接恢复或彻底删除条目，不再只能依赖右键菜单。
- 文件管理的桶挂载现在会先弹出挂载设置框，支持选择自定义挂载路径，并可切换只读挂载模式；后端挂载层会在只读模式下拒绝写入、删除和改名。
- 设置页现在支持配置挂载写入后的异步推送等待时间，并把默认 quiet period 从 60 秒缩短到 10 秒；Go 写回队列会按 `writeback_quiet_seconds` 调度后续等待上传任务。
- 回收站现在支持手动彻底删除单项、批量删除选中项，以及一键清空当前存储桶回收站；新配置默认关闭自动清理，不再默认按保留天数后台删除回收站内容。
- 设置页现在支持配置缓存目录；未自定义时默认使用工作路径下的 `cache/`，即 macOS/Linux 的 `~/.cloud-volume/cache` 或 Windows 安装目录下与 `cloud-volume.exe` 同级的 `cache/`，文件预览缓存与挂载缓存都会落到该目录下。
- 账号管理现在支持多个上游账号：账号 profile 会记录存储类型，页面直接展示所有账号，不再按上游类型分组，并保留和桶列表一致的卡片 / 表格视图切换；新增和编辑账号时先选择 S3 对象存储或 WebDAV，文件管理的桶列表也会展示当前来源账号和存储类型；后端文件浏览、上传、下载、复制、移动等基础存储操作已抽象到统一 storage backend，并新增 WebDAV 上游实现。
- 默认配置与运行时目录现在统一改为 Cloud Volume 命名：macOS/Linux 使用 `~/.cloud-volume`，Windows 使用安装目录下与 `cloud-volume.exe` 同级的 `config.toml` 和 `runtime/`；升级启动时会从旧的 `~/.remote-storage/config.toml` 或 `~/.remote-storage/profiles/*.toml` 复制配置到新位置，Windows runner 与安装器入口文件也改名为 `cloud-volume.exe`。
- Windows 启动窗口在高 DPI 小屏幕上的初始尺寸与居中坐标现在统一按逻辑像素计算，不再把物理工作区坐标再次按缩放倍率放大；因此首屏窗口不会再偏到屏幕右下角。
- Windows Cloud Files watcher 现在会把 Office `~$*.docx/xlsx/pptx` 锁文件和常见 `~wr*.tmp` 临时文件视为本地临时噪声，不再送进远端写回队列；同时本地文件若在 quiet period 内已被删除/改名，对应等待中的 writeback 任务会立即取消，不再残留成长期“等待同步”。
- Windows 安装包构建链路现在支持注入 Authenticode 签名参数，便于在 release workflow 或本地发布时使用企业/EV 证书对 `installer.exe` 做签名和时间戳，减少 SmartScreen 把安装包判为未知发布者的概率。
- 修复 `go/mount` 在 Windows 构建路径上的重复 `readRemoteRange` 声明，避免 CLI 打包与相关 CI workflow 在编译阶段直接失败。
- GitHub Actions tag 发布现在会在部分矩阵任务失败时继续收集已成功构建的产物并创建 release，不再因为个别平台打包失败而整次发布中断；同时 CLI 发布矩阵会把 `lite/full` 变体正确传给打包脚本。
- macOS WebDAV 挂载读取任务现在按“单个已打开文件”聚合到任务队列，不再把 Finder 的每次分块 range 读取都显示成一条独立下载任务；任务详情会额外显示当前访问的 `bytes=start-end` 范围，便于区分正常 lazy read 与异常循环读取。
- macOS 挂载调试日志现在会显式记录 `cleanup-stale`、`mount-volume`、`unmount`、`open-mount-path` 与 WebDAV mount probe 各阶段，并给相关系统命令加上超时，避免旧挂载残留或系统挂载命令卡住时前端只表现为一直转圈但 bridge 日志停在入口行。
- “关于”页版本信息现在统一走构建时注入的 `APP_VERSION_LABEL`：本地开发构建默认显示 `dev`，CI/tag 发布构建会显示对应版本号，不再依赖平台包元信息。
- CLI 与 Web 运行时现在都支持直接输出版本号：顶层 `cloud-volume-cli version/--version` 继续保留，`cloud-volume-cli-full web version/--version` 与独立 `cloud-volume-web version/--version` 也会直接打印当前构建版本。
- 设置页现在新增独立的“关于”子 Tab，并通过运行时版本信息展示当前应用版本，同时补充作者版权 `三千` 和 QQ 交流群 `572532027`。
- 发布体系现在新增 `cloud-volume-cli-full` 变体：保留原有 `cloud-volume-cli` lite 包和独立 `cloud-volume-web` 包不变，同时额外发布内嵌 Flutter Web 静态资源的单文件 full CLI，提供 `web` 子命令启动浏览器控制台，并把对应构建说明同步到了 README、Release 文案和 GitHub Actions workflow。
- Windows 桌面窗口启动位置现在会按主屏工作区居中计算，不再每次都固定从左上角打开。
- Windows 本地启动脚本现在同时兼容 PowerShell 风格的 `-Build` / `-SkipPubGet` 与常见的 GNU 风格 `--build` / `--skip-pub-get`，避免误把“仅构建”命令当成调试启动执行。
- 桌面端文件管理首页在获取存储桶列表失败时，错误提示现在除了“重试”外还会显示“重新配置认证信息”，可直接跳回 AK/SK/Endpoint 配置页修改后再重试。
- Windows 托盘图标现在会按新版通知区域回调格式处理左键恢复与右键菜单事件，最小化到托盘后可以重新弹出“显示主窗口 / 退出云卷”菜单，不再出现右键无响应导致无法关闭的问题。
- Windows 安装包现在始终显示安装目录页面；即使复用上一次记住的安装路径，升级安装时也仍然可以手动改到新的目标目录。
- macOS 和 Windows 托盘菜单现在都会显式处理右键菜单事件，避免依赖平台默认行为导致右键无响应或菜单一闪而过。
- Windows 安装包的默认安装目录现在固定为 `C:\Program Files\Cloud Volume`，不再直接使用中文产品名作为安装路径，以降低部分环境和第三方组件在中文路径下的兼容性风险。
- macOS 打包 DMG 内置的修复辅助脚本从可双击的 `双击修复已损坏问题.command` 改为纯文本 `修复已损坏问题.txt`。原来的 `.command` 文件本身也会被 Gatekeeper 加上隔离属性，双击时同样提示「已损坏」要移到废纸篓，反而误导用户。改用纯文本引导后，用户只需按说明在终端执行 `xattr -dr com.apple.quarantine /Applications/云卷.app` 即可。
- macOS 托盘图标恢复使用内置品牌模板资源，并按侧边栏品牌图的横向比例设置尺寸，避免状态栏里的云形被方形缩放挤压得不自然。
- 修正打包桌面版启动时的 bridge 加载顺序：应用现在会优先使用 bundle 内置的 Go bridge 动态库，只有开发环境下才回退到仓库根目录与本地 `bin/bridge` 构建路径，避免 release 包启动时报 `Could not locate the Remote Storage repository root.`。
- Release 文案生成脚本现在会自动附带更新记录、问题修复、macOS “已损坏” 处理方法、国内 GitHub 加速下载说明，以及构建产物的校验和与体积信息，后续 tag 发布不再只有纯资产清单。
- GitHub Actions 发布矩阵里的 Linux 桌面 GUI 产物现已收敛为 `amd64` 单架构，因为 Flutter 当前不支持在 Linux `x64` runner 上直接 cross-build 出 Linux `arm64` 桌面包；Linux `arm64` 仍继续发布 CLI 与 Web 运行时归档。
- Windows Cloud Files mounts now keep a stable sync-root path at `~/Cloud Volume/<bucket>` instead of allocating a timestamped directory on every mount, so Explorer paths, remount recovery, and task references no longer drift across sessions.
- Windows Cloud Files cached writeback persistence no longer depends on a single shared `writeback.db` lock. Each mount process now writes its own queue snapshot under `~/.remote-storage/runtime/mounts/<bucket>/writeback/queue-<pid>.json`, remount recovery compacts old queue files back into the active process, and leftover crashed runners no longer block the next mount just by holding a stale queue DB handle.
- Linux CLI FUSE 挂载新增 `--auto-sync` 和 `--worker`：顺序追加写现在可以在后台预上传已经完整落盘的 multipart 分块，最终仍保留 quiet-period 自动推送和卸载 drain 推送来补齐尾块并完成 multipart；multipart 并发默认按 CPU 核数动态收敛到 `4..10`，也可以通过 `--worker` 显式放大以适配更高的内网上传带宽。
- Linux 挂载缓存文件路径现在按对象路径 hash 平铺到每个 bucket 的本地 `cache/` 目录，避免深层对象路径把本地写回缓存展开成层层子目录，同时保留原有远端 key 与桌面端逻辑不变。
- Makefile 现在提供 `make cli` 作为本地 CLI 构建入口，并新增 `make cli-release` 一次性打包 Linux `amd64/arm64`、macOS `amd64/arm64`、Windows `amd64` 的 CLI 发布包，和现有 GitHub Actions CLI 发布矩阵保持一致。
- Added `cloud-volume-cli` for headless Linux usage: `init` now prompts for endpoint / AK / SK / bucket / root-prefix / path-style config and saves to the existing TOML store, `mount` can foreground-mount a chosen bucket to either the default `~/Cloud Volume/<bucket>` path or a caller-specified empty directory without changing the existing desktop mount flow on macOS, Windows, or Flutter, and the CLI now also exposes `status` and `unmount` subcommands for scripted server-side mount management.
- `cloud-volume-cli` now defaults into an interactive shell when started without arguments, keeps a current bucket plus remote working directory, supports `cd` / `pwd`, and adds direct object commands `put`, `get`, `ls`, and `list` on top of the existing S3 config and root-prefix rules.
- `cloud-volume-cli` now also supports `mkdir` plus hard-delete `rm/delete`, recursive directory `put/get`, and shell-side persistent history plus tab completion for commands and remote paths.
- `cloud-volume-cli init` no longer prompts for `root_prefix`; first-run setup now only asks for the core connection and auth fields, while any existing stored `root_prefix` remains untouched.
- `cloud-volume-cli init` no longer requires picking a default bucket up front: after collecting endpoint and credentials it now lists buckets for optional arrow-key selection, and later bucket-scoped commands can trigger that same selection flow on demand when no default bucket is stored.
- `cloud-volume-cli` now also exposes `bucket` and `bucket list`, so shell users can switch buckets from an arrow-key picker and direct CLI users can inspect the bucket list or set the active bucket without editing config manually.
- Linux CLI FUSE unmount now blocks on the current bucket's queued writeback tasks before the mount is released, so `Ctrl+C` waits for pending delayed uploads to finish instead of dropping straight into unmount while local cache files still have not been pushed.
- Mounted multipart writeback uploads now keep the existing resumable `.uploading.json` state but upload pending parts with bounded concurrency instead of strict serial order, so large files such as multi-GB `dd` outputs can push multiple S3 parts in parallel while still resuming from already completed parts after interruption.
- Release automation now also builds standalone CLI archives for Windows `amd64`, macOS `amd64/arm64`, and Linux `amd64/arm64`, and publishes them alongside the existing desktop release assets.
- Tagged release automation now also publishes Linux Web runtime archives for `amd64` and `arm64`, each bundling the `cloud-volume-web` server binary with the built Flutter Web static assets so browser deployments can be unpacked and served directly.
- Added a new Web runtime alongside the existing desktop FFI flow: Flutter Web now boots through a Go HTTP server, requires Cookie-backed login before opening the console, exposes per-bucket WebDAV URLs instead of local mount actions, supports browser-native upload/download, and persists WebDAV credentials in setup plus Settings without echoing saved passwords back to the client.
- The Web shell now uses the `Cloud Volume / 云卷` browser title and branded app icons, replaces the left-top SVG text path with Flutter-rendered Chinese text so the sidebar logo no longer degrades into `xx` on web, and shows a branded preload screen while fonts, CanvasKit, and app resources are loading instead of leaving a long white screen.
- Web first-run setup no longer asks for WebDAV username/password up front; it now saves S3 credentials only, defaults WebDAV/browser-login credentials to the current `AK/SK`, auto-signs the browser into the first session after setup, and still allows overriding WebDAV credentials later from Settings.
- Windows mount startup no longer panics when a leftover `remote_storage.exe` still holds `~/.remote-storage/runtime/mounts/<bucket>/writeback.db`; the bridge now returns a normal actionable error instead, and Windows Settings add an `结束残留占用进程` recovery action for cleaning those stale local runner processes before retrying the mount.
- Windows Cloud Files cached-writeback now persists queued uploads in a per-bucket BoltDB store, merges repeated edits by virtual path, restores unfinished writeback tasks after remount, and releases unmount without synchronously flushing the whole queue first, so Explorer writes no longer have to wait for pending uploads before the mount disappears and background sync can continue while the app process stays alive.
- Windows Cloud Files directory-copy recovery now refreshes parent harvest scans when descendant files and child directories keep appearing, and local directory writes clear stale placeholder markers under that subtree, which fixes interrupted large-folder copies that previously only surfaced the first discovered child tree or only queued first-level files while deeper subdirectories such as `.git` stayed missing from the transfers page and mounted file manager.
- Windows Cloud Files unmount now disconnects the provider before closing the local watcher, and watcher shutdown waits for active harvest scans to stop scheduling new directory watches, which fixes mounts getting stuck at `watcher-close-start` during unmount after large copy operations.
- Windows mounted writeback uploads now run through a bounded `ants` worker pool instead of launching one upload goroutine per queued file, and the pool size is configurable as `windows_writeback_concurrency` from Settings, which prevents large Explorer copies from exploding into hundreds of concurrent upload tasks, reduces follow-on `context deadline exceeded` failures under overload, and keeps the desktop UI more responsive while the writeback queue drains.
- The transfers page multi-select list now reuses the same rounded selection control, header treatment, and row hover/press/selected styling as the mounted file-manager list, so batch-selection behavior looks and feels consistent between task management and object browsing.
- The transfers page now keeps the same bottom breathing room as the file-manager and recycle-bin pages, so the final task rows no longer feel visually stuck to the window edge when scrolled to the end.
- The settings page now splits platform-neutral preferences and Windows-only mount controls into separate in-page tabs, so general settings stay shorter while non-Windows builds no longer surface a Windows settings tab at all.
- The file-manager sync badge now treats non-mounted object lists as already synced instead of showing a separate “unmounted” state, which better matches the expectation that remote-only browsing has nothing pending for desktop writeback.
- Windows desktop startup now opens with a tighter default window size and slightly smaller monitor-based width/height caps, so the app no longer feels overly wide on 1080p and 2K displays before any manual resize.
- Windows and macOS desktop startup now shrink the initial window on smaller displays using the same adaptive sizing approach already used on Linux, so the first-run layout stays fully visible on lower-resolution laptops instead of opening oversized.
- The transfer queue now supports row selection plus batch start and batch cancel actions, so waiting uploads and active jobs can be resumed or stopped in bulk from the transfers page instead of one by one.
- Windows Cloud Files watcher recovery now re-arms the currently opened placeholder directory itself when Explorer fetches that directory, moves raw watcher `Add/Remove` work off the event-processing path, and starts consuming watcher events before the initial directory rescan, which fixes the cases where copying a folder into an already opened nested directory such as `bakcuptest/test/test2` still produced no upload task and where later unmounts or pre-existing directory rescans could wedge around watcher shutdown.

- GitHub Actions 桌面发布流程现在只会在推送形如 `v0.0.1` 的标签时触发，并自动发布 macOS `universal/arm64` 的 `dmg+zip`、Windows `amd64` 的 `installer.exe+zip`、Linux `amd64` 的 `tar.gz+AppImage`。
- Linux 自定义标题栏现在会使用应用内右上角窗口控件；GTK 应用显示名也显式改成 `云卷`，避免任务栏继续显示 `remote_storage`。
- Linux 首次启动窗口现在会按屏幕尺寸再缩小一档，关闭按钮会弹出“最小化窗口 / 退出云卷”确认，登录表单改为真正的垂直居中可滚动布局。
- 初始化配置、启动检查和文件管理里的 Go bridge 错误现在会转换成更友好的中文文案，像 S3 `SignatureDoesNotMatch` 这类常见密钥/签名错误会直接提示检查 AK/SK 与签名配置。
- 桶列表表头里的 `操作` 列和每一行的固定按钮槽位重新对齐，挂载、卸载、回收站和打开挂载目录操作不再左右参差。
- Linux 桌面宿主现在会隐藏系统标题栏，并使用与 Windows 一致的应用内右上角最小化 / 最大化 / 关闭控件。
- Linux 启动窗口现在会按当前显示器尺寸自适应，首次登录页也改成可滚动的垂直居中布局，避免保存按钮在大窗口里显得过低或在小窗口里被挤出可视区域。
- 首次启动登录页现在包进了居中的圆角壳，左右两栏不再贴满窗口边缘，视觉上更接近桌面应用窗口。
- Linux bucket mounts now use a FUSE backend rooted at `~/Cloud Volume/<bucket>`, reusing the existing local cache, overlay visibility, delayed writeback queue, and mounted-object UI sync model instead of returning platform-unsupported errors.
- Linux desktop startup now builds `bin/bridge/libremote_storage_bridge.so` as part of the runner build, installs it into the Linux bundle, and teaches the Dart loader to resolve the bundled `lib/` copy so packaged launches no longer depend on the repository layout.

- The file-manager object list now comes from the mounted local-first directory view when a bucket is mounted, so pending writeback items appear in the list and the sync status stays in a dedicated column instead of repeating under the name.
- Windows Cloud Files sync roots now project mounted writeback queue state back into Explorer via `CfSetInSyncState`, so files queued by the cached/writeback path show native not-in-sync status until the delayed upload completes and then flip back to in-sync.
- Mounted bucket file lists now show a per-item sync badge in both list and grid mode, so files and directories can surface `已同步`, `等待同步`, and `同步中` state inline instead of only through the header badge or transfers page.
- The file-manager header now surfaces per-bucket mounted writeback status directly in the mount badge, showing `等待同步 N` and `同步中 N` counts without making users switch to the transfers page to confirm whether desktop edits are still queued for remote sync.
- Windows Cloud Files mount-status polling no longer re-runs the sync-root write probe on every periodic `get_bucket_mount_status`, which stops the app's own health check from mutating `.cloud-volume` inside the mounted root and retriggering repeated Explorer placeholder refreshes.
- Windows Cloud Files browsing now suppresses cached/coalesced placeholder refresh logs and no longer prints every periodic mount-status probe, which keeps bridge logs focused on real placeholder and write-path failures such as unresolved-name copy errors.
- Windows Cloud Files placeholder population now coalesces repeated directory fetches and skips `CfCreatePlaceholders` for paths that already exist locally, which avoids Explorer placeholder refresh loops and reduces `The cloud operation is invalid` / `Access is denied` callback failures while browsing mounted folders.
- Windows local run script now appends `127.0.0.1,localhost` to `NO_PROXY` when proxy variables are present, which prevents `flutter run` from sending local Dart VM service websocket traffic through an HTTP proxy and losing the debug connection while the app stays open.
- Windows Cloud Files mount startup now runs its write probe in-process with short retries instead of spawning a separate PowerShell writer, which avoids false mount failures caused by slow probe startup.
- Windows Settings now include a force-reset mount action that calls `cleanup_mounts` to clear stuck bucket mounts, stale sync roots, and cached mount state before retesting Explorer write flows.
- Windows Cloud Files remounts now allocate a fresh sync-root directory and force a rebuild when the same bucket's mount configuration changes, which avoids reusing stale sync-root registration state across mount attempts.
- Flutter now runs synchronous Go bridge calls on a background isolate before touching the FFI layer, which keeps startup, bucket refresh, mount-status checks, and metadata probes from freezing the desktop UI while the bridge waits on network or mount work.
- The Go bridge now mirrors runtime diagnostics to `~/.remote-storage/runtime/logs/bridge.log`, and Windows Cloud Files hydration logs now include placeholder fetches plus aligned transfer ranges for mount-debugging.
- Windows mount settings now expose three selectable modes: `cloud_files_cached` to keep the Cloud Files shell while reusing the existing cached-download and async writeback flow, `cloud_files_direct` to keep the earlier direct-S3 hydration path for side-by-side testing, and `webdav` as the mapped-drive fallback.
- Windows bucket mounts now default to the same WebDAV-backed mount model as macOS, while the optional Explorer `This PC` entry is disabled by default and can be enabled from Windows Settings.
- The Windows desktop shell now keeps a native tray icon with show/exit actions, and the custom close button prompts to hide to tray or quit instead of exiting immediately.
- Windows list rows now show hover and press feedback on click, and the bootstrap config-check card is smaller and less visually heavy during startup.
- The Windows host shell now uses the same `云卷` app icon as macOS, drops the native title bar, and replaces it with app-owned top-right window controls plus a native bridge for drag/minimize/maximize/close actions.
- Windows desktop startup now builds the Go FFI bridge with CGO enabled, compiles the shared mount package without macOS-only xattr code, and stages `remote_storage_bridge.dll` next to the runner so both `flutter run -d windows` and built executables can launch.
- The settings page now keeps extra bottom breathing room below the final action row, so the lower section no longer feels visually stuck to the window edge when scrolled to the bottom.
- Trash listing, restore, and permanent delete bridge calls now run off the Flutter UI isolate so opening the recycle bin no longer freezes the app while S3 metadata is scanned or retention cleanup runs.
- The recycle-bin page now hides mount, upload, and new-folder actions so its action bar only shows controls relevant to trash browsing.
- The sidebar now exposes a dedicated global recycle-bin page that works one bucket at a time: it automatically opens the first bucket that actually has deleted items, falls back to the first configured bucket when all are empty, and still lets users switch buckets manually for restore and purge management.
- The global recycle-bin page now supports keyword search, per-bucket switching, batch restore, and batch permanent delete, while each entry keeps a direct checkbox for multi-select.
- Successful recycle-bin restores now show immediate feedback, force-refresh the currently open trash bucket immediately, and notify the cached file-manager page so matching bucket/prefix object lists are silently refreshed instead of staying stale after a restore.
- Lightweight success and error feedback now consistently use the app's shadcn_ui toast layer instead of Material `SnackBar`/`ScaffoldMessenger`, so pages, dialogs, and restore flows no longer depend on a separate Material feedback stack.
- Loading spinners, tooltips, breadcrumb overflow navigation, transfer-row actions, and sidebar task affordances now all use the same shadcn_ui-aligned component wrappers, which removes the last visible Material-style stragglers from the desktop shell.
- The global recycle-bin results now reuse the same fixed-header file list style as the main file manager, with original-path subtitles, header select-all, and right-click restore/delete actions, while removing the cross-bucket aggregate layout.
- Files now expose a `创建分享` context-menu action that generates a presigned download link with a configurable lifetime, and the sidebar now includes a share-management page that reuses the app's standard file-list layout, adds checkbox multi-select for batch deletion plus inline `详情 / 删除` row actions, and keeps full-link inspection inside a dedicated details dialog for copying and renewing share records.
- Share creation and renewal dialogs now include common duration presets, and share records can open their links directly in the default browser.
- The transfer queue now supports keyword, status, and task-type filters for faster troubleshooting of long-running or failed jobs.
- The transfer queue now persists its recent task list in local app storage and restores it on the next launch, so a sudden app close no longer clears the queue; unfinished tasks from the previous session reappear as interrupted failed entries for follow-up instead of vanishing.
- The file-manager action bar now adds a left-side search box for bucket lists, object lists, and per-bucket trash lists, and select-all now respects the filtered visible results.
- File lists, bucket-trash lists, and the global recycle-bin page now fetch data in pages and continue loading on scroll, which avoids long first-load stalls when a bucket contains many objects or deleted entries.
- Recycle-bin paging no longer blocks on synchronous retention cleanup, and each trash page now loads entry metadata with bounded concurrency plus a smaller first page size so the recycle-bin screen opens much faster on large buckets.
- New trash entries now persist a key-encoded index alongside the soft-deleted payload, so recycle-bin pages can reconstruct full metadata directly from list results; older JSON-based trash entries are also repaired opportunistically into the new index format after they are read.
- The desktop UI now embeds Source Han Sans CN in the app bundle and uses it as the global theme font, which keeps typography consistent across macOS, Windows, and Linux instead of depending on each system's fallback fonts.
- Large delayed mounted uploads now use resumable multipart writeback instead of restarting from a single timeout-bound `PutObject`, so Archive Utility and other WebDAV-driven extraction flows can continue from already uploaded parts after failures or long stalls.
- Canceling a queued or already-running mounted upload from the task queue now also clears its local staged/cache file and persisted multipart resume state, which prevents canceled extraction outputs from reappearing in the mounted file list or being re-uploaded later.
- Bootstrap a Flutter desktop shell with a Go FFI bridge and first-run remote storage configuration flow.
- Transparent macOS titlebar with content extending behind traffic lights.
- Left-right split config page: dark brand panel + form.
- User-switchable accent color with 5 presets, persisted across restarts.
- File manager now uses the Local-cloudPan SVG icon set for list and grid views.
- Buckets and sidebar navigation now use matching custom SVGs instead of reusing folder icons.
- macOS file picking now includes the required `file_picker` user-selected file entitlements.
- Grid mode is denser, with tighter spacing and more compact Finder-style tiles.
- Sidebar page switches now preserve in-memory page state through an `IndexedStack`.
- Sidebar footer now shows live transfer activity, aggregate speeds, and a hover task list for recent uploads/downloads.
- Sidebar footer now adds a task-count badge while uploads or downloads are pending.
- File manager now keeps breadcrumbs and actions in one header row, collapses long middle path segments into `...`, and still supports in-place folder creation plus `..` parent entries in non-root directories.
- WhiteSur SVG assets are vendored in-repo as an optional secondary icon library.
- Sidebar, bucket, and transfer entry icons now use Fluent System Icons for a more native app-style navigation set.
- Added a custom SVG app mark and Chinese product name `云卷`, applied to the sidebar brand area and macOS app icon/name.
- Added a macOS menu bar status icon that can reopen the main window, and refreshed the rounded Dock icon to match the `云卷` brand.
- The macOS tray exit action now exits immediately without an extra confirmation dialog.
- The macOS tray now uses a dedicated logo-only template icon asset, and the default main window size is smaller.
- The macOS main window now reopens at the default centered size on launch instead of restoring the prior session size.
- New folder creation now uses a MinIO-compatible zero-byte directory placeholder flow for better S3-compatible endpoint support.
- Added a configurable default download directory in settings, with fallback to the system Downloads folder.
- File and folder items now support right-click rename and delete actions in both list and grid views.
- Upload now supports selecting multiple files at once, and active upload/download tasks can be canceled from the transfers page and sidebar hover card.
- Breadcrumbs now stay fully expanded when there is enough room, and collapse the oldest left-side path segments into `...` only when the header becomes narrow.
- Added a default-on setting to hide files and directories whose names start with `.`, while still allowing users to reveal them from Settings.
- Clicking a file now first sends a `HEAD` request to validate the SQLite-tracked local cache against the remote file size and last-modified time; stale cache entries are discarded and re-downloaded before opening, while the context menu keeps an explicit download-to-path action.
- List mode now adds a fixed header and aligned Name, Size, and Modified columns so file metadata occupies the right side cleanly.
- File item context menus now open faster, ensure only one menu stays visible, and close first when the user clicks another file or folder.
- File and folder items now always open on single click, and multi-selection stays available through explicit checkmarks plus batch download and batch delete actions in the file action bar.
- Closing the main macOS window now asks whether to minimize to tray or quit, while the tray menu's `退出云卷` action still exits immediately.
- List view now adds a header checkbox that can select or clear all visible items in the current directory, with partial-selection feedback.
- The desktop project now includes macOS, Linux, and Windows host shells, and the local build scripts support native bridge/build flows on all three platforms.
- Added a tag-triggered GitHub Actions desktop release workflow that now publishes 7 release lanes on tags such as `v0.0.1`: macOS `amd64`, macOS `arm64`, macOS `universal`, Windows `amd64`, Windows `arm64`, Linux `amd64`, and Linux `arm64`, with macOS `zip + dmg`, Windows `zip + installer.exe`, and Linux `AppImage` outputs.
- Added the first macOS bucket-mount flow: the active bucket can now be mounted as a Finder-visible system WebDAV volume via a local anonymous WebDAV server, and the file manager action bar now exposes mount, unmount, and open-mount actions.
- The bucket list now also exposes direct per-bucket mount, open, and unmount actions, so mounting no longer requires entering the bucket first.
- Mounted-volume reads now populate the existing transfer queue through tracked background downloads with reusable local cache files, while writes first land in a local staging area and then upload asynchronously as cancelable transfer tasks.
- Mounted-volume writes now stay in a local cache and local metadata overlay first, then flush to S3 after a 1-minute quiet period; pending local edits also survive rename/move/delete operations inside the mounted WebDAV view instead of uploading immediately on file close.
- The task queue now shows delayed mounted uploads immediately as `等待同步` items, and those pending writeback tasks can be canceled or forced to `立即同步` from the UI before the quiet period elapses.
- Object copy and move operations now also feed the same Go-side transfer hook layer, so explicit file-manager copy/move actions and mount-triggered remote moves appear in transfer management with progress and cancellation instead of bypassing the task system.
- The transfer queue now keeps an idle background sync loop so WebDAV-triggered reads, copies, and uploads appear in the transfers page even when Flutter did not create the task locally first.
- The new mount layer also adds short-lived metadata caching, next-level directory prefetch, per-request timeouts, and duplicate-request coalescing to keep Finder/WebDAV directory probing responsive on slower object stores.
- The mount cache now keeps a local metadata overlay for staged files, locally created directories, delete tombstones, and pending rename/move targets, so Finder directory listings stay stable during delayed writeback windows instead of reverting to stale remote metadata.
- The macOS mount flow now lets the system mount the local WebDAV endpoint as a real `/Volumes/...` WebDAV volume, while still seeding local-only system dot paths such as `.TemporaryItems` so Finder, Archive Utility, and similar tools can create writable temporary content without syncing those macOS-private files back to S3.
- Finder-style trash path moves on mounted buckets now treat `.Trash...` and `.Trashes/...` rename requests as real deletions of the remote object tree, while the app-level recycle bin remains hidden from Finder.
- WebDAV mount directory polling now downgrades single-entry metadata/listing failures into skippable path errors during `PROPFIND`, which avoids noisy `superfluous response.WriteHeader` warnings from the underlying Go WebDAV handler.
- The macOS mount layer now logs trash-related WebDAV `MOVE` and `DELETE` requests, including Finder-provided destination paths and overlay-boundary decisions, so trash failures can be diagnosed from the app log instead of guessed.
- Finder and Quick Look sidecar probes such as `._name`, `.hidden`, and `.Spotlight-V100` now map missing remote objects to proper `404 Not Found` WebDAV responses instead of `405`, which reduces probe noise and keeps macOS metadata discovery on the expected path.
- The mount layer now supports cross-directory file and directory moves, which fixes macOS Archive Utility flows that create temporary writable folders and then move extracted content into place.
- The macOS host now unmounts any active bucket mount during app termination, which prevents stale desktop mount entries from hanging on later access after the app exits.
- The bucket browser list view now includes a fixed header row so bucket names, types, and mount actions no longer render as an unstructured plain list.
- The bucket browser now supports right-click actions in both list and grid modes; list mode still shows explicit mount controls beside the new fixed header row, while grid tiles stay visually clean with only the bucket icon and name.
- Deletes now use an app-level bucket recycle bin instead of relying on Finder trash support from the mounted WebDAV volume: objects are soft-deleted into a hidden bucket directory such as `.trash`, can be browsed per bucket from the bucket list actions, restored, or permanently deleted from the in-app recycle bin view.
- Settings now expose the recycle-bin directory name and retention days, so the hidden bucket trash path and automatic cleanup policy can be adjusted without editing the config file manually.
- The mounted WebDAV view now hides the configured recycle-bin directory from Finder so the special trash area stays app-managed and does not appear as a normal folder on the desktop volume.
- Trash root detection now treats both `.trash` and `.Trash` as reserved recycle-bin paths, so existing app trash data and Finder-style trash naming stay protected and hidden consistently.
- Mounted delete handling now skips macOS `._*` sidecar files from the recycle-bin move path, rewrites MinIO-style directory placeholders directly instead of `CopyObject`-moving them, and retries just-written file deletes long enough for remote copy eligibility, which fixes recursive delete failures on freshly created directories.
- Bucket mount status now reconciles against the real macOS WebDAV mount table, so Finder-side manual unmounts are detected automatically and the file manager no longer stays stuck on a stale "已挂载" state.
- Full Chinese interface.
- The file-manager header now keeps breadcrumbs and action buttons on separate rows, and bucket-list mount actions use a tighter adaptive column so mounted actions such as `打开挂载目录` no longer render truncated after mounting.
- The bucket list now left-aligns its action column and hides the non-clickable `已挂载` badge in list mode, so mounted buckets keep a cleaner single-row action area with just actionable buttons.
- In the bucket list, the primary mount action now switches between `挂载` and `卸载` instead of showing a separate mounted-state badge plus an extra unmount button, which keeps mounted rows on a single cleaner action line.
- Mounted directory creation and temp-folder-to-final-folder moves now commit locally first inside the WebDAV view, then backfill remote directory placeholders and delayed uploads asynchronously, which keeps Archive Utility and similar macOS app workflows from failing when they immediately re-probe freshly moved extraction results.
- Nested Archive Utility and Finder temp paths such as `.AU.*`, `.ArchiveServiceTemp*`, and `.DS_Store` inside child directories are now handled by the local mount overlay too, so decompression and temp-file-heavy app workflows stop probing remote S3 state for every transient artifact.
- Nested local-overlay renames now create the destination parent directory before moving `.AU.*` / `.nosync` temp folders, which fixes the `403` failure that made macOS Archive Utility report it could not identify a writable temporary folder.
- Root WebDAV directory listings now ignore transient overlay parent directories that only exist to host nested `.AU.*` or `.ArchiveServiceTemp*` paths, which prevents root-level `PROPFIND depth=1` calls from failing with `500` after Archive Utility finishes and cleans up its temp folders.
- Mounted transfer operations now use a much longer timeout than metadata probes, so large read-ahead downloads and delayed writeback uploads are no longer cut off by the same short deadline used for `PROPFIND` and `HEAD`.
- Mounted reads now resume interrupted cache downloads from existing `.downloading` fragments when the remote object has not changed, reuse valid completed cache files immediately, and invalidate both full and partial cache artifacts automatically when the remote size or last-modified timestamp changes.
- Mounted WebDAV deletes now hide files and directories from the mounted view immediately, finish the actual bucket-side delete asynchronously in the background, and publish those background removals as `删除` tasks instead of blocking Finder on long recursive deletes.
- The macOS mount manager now clears stale `云卷-*` WebDAV volume entries during cleanup and before remounting the same bucket, which prevents duplicate `/Volumes/云卷-...-1/-2/...` mount names from piling up and timing out.
