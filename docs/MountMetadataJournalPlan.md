# 挂载元数据缓存与操作日志（Mount Metadata Journal）计划

> 状态：设计草稿 / 待排期。目标是解决“目录重命名 + 上传后远端缺失”这类队列状态丢失、路径推导不可靠的问题。

## 目标与非目标

目标（2026-08-17 更新：重心从“挂载写回”升级为“内部统一元数据缓存管理”）：

0. **统一视图**：文件管理页面与 mount（Finder/FUSE/WinFsp/Cloud Files）读取同一份元数据视图，而不是“挂载时借 mount 会话的缓存，未挂载时直连远端”。
1. 每个桶本地维护一份持久化元数据视图（文件、目录、tombstone）。
2. 每次本地变更先追加一条可跟踪操作记录（类似 git reflog / CAS commit），再异步同步远端。
3. 重命名按“同一个对象 ID 的路径变化”记录，不再靠字符串前缀重写路径。
4. 重启后能从本地视图 + 未完成操作日志恢复，不依赖内存队列。
5. 远端同步按依赖顺序执行并验证后置条件，目录 marker 先于子文件上传。
6. 远端变化（页面直连操作、P2P、轮询、挂载外第三方）以同一套对账流程进入视图，而不是旁路失效通知。
7. **本地 metadata 是缓存，不是新增真源**：开发环境下本地 inode tree 可丢弃、可清空，随时能从远端 listing 重建；只有其中尚未同步到远端的 pending 内容/操作按数据对待，verified 之后的部分都是可重建缓存。

非目标：

- 不做 git 兼容仓库，不引入远程 git 协议。
- 不做跨主机多写合并；冲突采用明确的“本地日志优先 + 远端变化报告冲突”策略。
- 不承诺 macOS WebDAV 挂载点对外暴露稳定内核 inode；WebDAV 协议本身不透传 inode。

## 现状盘点：统一视图前必须知道的耦合（2026-08-17 review）

### 页面与 mount 的旧数据通路（M7 已替换 metadata profile 路径）

- 历史行为：`bridge/dispatch_paging.go` 的 `listObjectPage` 曾经先走 `mount.ListMountedObjectPage`，只有该桶当前挂载会话存在时页面才使用挂载视图；否则直接 `storageops.ForConfig(...).ListObjectsPage` 连远端。现在有 `ProfileID` 的页面请求先走 metadata，`ListMountedObjectPage` 只保留给无身份 legacy fallback。
- `go/mount/object_page.go`：挂载视图来自 `bucketAccess.cache`（内存）+ `localOverlay` + `pageViews`（2 分钟、最多 16 份的快照分页）。未挂载时这套东西完全不存在。
- `bridge/dispatch.go` / `go/webapi/invoke.go` 的上传/建目录/删除/重命名：先写远端，成功后调用 `mount.NotifyExternal{Upload,Delete,Rename}` 反向修补挂载缓存。也就是“页面操作 = 远端真源 + 旁路失效通知”，与“mount 操作 = 本地先行 + 异步写回”方向相反。
- P2P：`peer_refresh.go` 直接调 `pollRemoteDirectory`；轮询：`remote_poller.go` 只刷新最近最多 12 个被访问目录，且依赖后端 `SupportsMountRemotePolling`。
- 结论：今天至少有 5 条数据来源（挂载写、页面写、P2P、轮询、第三方远端变化），页面视图只是“挂载会话的缓存投影”，不是独立元数据层。

### 与“统一元数据缓存”直接冲突的实现事实

- `bucketCache` 是**纯内存**，按字符串路径组织：`objectCache/listCache/localFiles/localEntries/deletedPaths` 五张 map。目录 rename 通过遍历 `strings.HasPrefix` 重写 key，且会同步 `os.Rename` 本地缓存文件；路径身份与文件身份完全混在一起。
- `ListMountedObjectPage` 在 manager 持锁期间同步探测挂载活性（`syncSessionLocked` → `IsActive`，有 TTL 缓存但仍是会话级 IO），未挂载则直接落远端 —— 统一视图必须去掉“是否有挂载会话”这个分支。
- `object_page_snapshots` 的 continuation token 是**进程内** `m:<snapshotID>:<offset>`，重启后 token 即失效；快照本身 2 分钟过期、最多 16 份，不能作为持久分页游标。
- `NotifyExternalRename` 实现为“删旧路径 + 当作新上传”，会把 mount 侧 pending 写回的路径判断搞混（外部 rename 与本地 rename 语义不对称）。
- `InvalidateExternalUpload` 会 `removeLocalPath`（**顺带删除本地缓存文件**）：页面覆盖上传同名文件时，若 mount 有 pending 写回，本地数据可能被误删（恢复条件依赖 cacheRoot）。
- `localOverlay` 负责系统临时目录（.Trash/.fseventsd/AppleDouble 等），其过滤规则分散在 `overlay.handles`、`filterTrashItems`、`isLocalMetadataPath`；统一视图必须决定这些“仅 mount 可见”的命名空间如何表示（建议：overlay 永不出现在持久元数据里）。
- trash 是**远端目录别名**（`TrashDirectoryAliases`），mount 侧隐藏；页面 `listTrashPage` 走独立后端 API。统一视图中 trash 应该是同一棵树的带标记子树，而不是另一个 API 世界。
- Windows Cloud Files 的 rename 是事件回放（`handleRename` → `enqueueRenamePath`），watcher 用本地路径 + `MarkRenameSource/Rebase` 维护身份；OID 化时这是最大的平台迁移面。
- `manager.sessions` 以桶名为主键、单会话；`newBucketAccess` 每次创建新的 cache/dirSync/writeback。元数据存储的生命周期应从 mount session 解耦（挂不挂载都存在），否则“未挂载时页面”仍然没有视图。

### 明确的风险清单（进入 TODO 前）

1. **正确性风险：页面写与挂载写方向相反。** 页面写 = 远端成功才算成功 + 通知挂载失效；mount 写 = 本地先成功、远端异步。若统一视图先服务页面读、仍保留两套写路径，会出现“页面显示成功但 journal 还没排到”或相反的倒挂。必须先定义写入顺序契约：任何入口（页面/mount/P2P）都先落统一视图 + journal，再异步远端。
2. **数据丢失风险：`InvalidateExternalUpload` 删除本地路径。** 页面上传/建目录会清掉 mount pending 数据。统一视图落地时这个函数语义必须改为“按 OID 合并远端确认，不删 OID 仍 pending 的本地内容”。
3. **身份迁移简化。** 现有缓存、写回条目、mutation 记录按路径组织；开发环境不做路径→OID 导入器，直接从远端 listing 物化新 inode。Cloud Files watcher / P2P 的路径事件在接入点即时解析成本机 inode，而不是持久化路径状态。
4. **锁与生命周期风险。** `manager.mu` 同时保护会话生命周期与对象页读取入口；统一视图要变成常驻服务，不能挂在挂载会话生命周期下，也不能在持 manager 锁时做远端 IO。
5. **分页/一致性风险。** `m:<id>:<offset>` token 进程内有效；改为持久视图后，token 语义要重定义（推荐 listing cursor + 已知不一致窗口，而不是假装强一致快照）。
6. **冷启动风险。** 统一视图首次构建需要全量 listing；大桶（百万对象）不能阻塞页面首屏。需要“目录级惰性物化 + 根目录优先”的 bootstrap 策略。
7. **平台投影风险。** Windows Cloud Files / WinFsp 的本地 sync root 状态由平台管理，视图状态变化要投影到 placeholder，失败会回到现在这类 Explorer/页面不一致问题。
8. **多客户端/P2P 风险。** 当前 P2P 广播携带路径 + versionHint；OID 化后协议要兼容或协商，避免旧客户端把 OID 事件当路径事件处理。
9. **只读挂载与权限。** `readOnly` 目前在 bucketAccess 上；统一视图下页面写、挂载写、同步器写共用视图，权限检查必须显式分层（视图允许本地草稿，远端同步阶段拒绝写）。
10. **重建/回滚（开发环境简化）。** 本地 metadata 是可从远端重建的缓存：不做旧 writeback/mutation JSONL 迁移，不保留旧队列 feature flag；schema 不匹配或损坏时清空 namespace 重建。唯一例外是未同步到远端的 pending content——清空动作必须先确认没有 pending 操作，或明确警告会丢弃未上传开发数据。
11. **namespace 风险。** 现有 mount runtime/cache 只按 `safeSegment(bucket)` 分目录，既可能碰撞，也没有稳定 profile 身份。metadata store 若复用这个规则，会把不同账号、同名 bucket 或不同 rootPrefix 混到同一棵 inode 树。
12. **远端 rename 身份风险。** OID 只能追踪本机产生的 rename；generic 远端 listing 无法可靠判断两个不同路径是否是同一个对象。禁止依据 size/mtime 自动配对，否则会把无关文件合并成一个 inode。
13. **写入原子性风险。** bbolt 与内容文件是两个持久化介质；必须采用“先写 pending content 并 fsync 文件/目录，再提交 inode+journal 事务”的顺序。反过来会留下 journal 指向不存在内容；正向崩溃只会留下可 GC 的孤儿 content。
14. **B+Tree 写竞争风险。** bbolt 每次只允许一个写事务。Finder/Explorer 的批量复制会产生大量 create/write/rename 事件，事务中绝不能做网络 IO 或全树扫描；需要短事务、批处理边界和 per-inode/parent 冲突检测。
15. **路径解析/cycle 风险。** 路径由 inode parent 边递归推导后，错误的跨目录 rename 可能形成 cycle。rename 必须做祖先检查，路径生成必须有最大深度/visited set 防御，损坏数据应进入 store-corrupt 状态而不是无限递归。
16. **内容缓存身份风险。** 当前 cache 文件路径由 virtual path hash 推导，目录 rename 会移动缓存文件。切到 inode 后 pending content 必须按 `inode + generation` 命名，已同步读缓存可以被逐出，但 pending content 永远不能被 cache-cleanup 当作普通缓存删除。
17. **桥接协议风险。** `ObjectInfo` 目前只有 key/size/mtime/etag/isDir，Dart Web 也可能消费它；新增 uint64 inode、view revision、sync state 时必须用 string 编码和向后兼容字段，避免 JavaScript 53-bit 截断。

## ContextFS 可参考结论

- `src/cas/working_tree.h/.cpp`：两级 COW path map（immutable base + delta overlay，含 whiteout tombstone，`base_authoritative_` 控制 bootstrap 期间的回源策略）。适合作为本地元数据视图的内存结构参考：启动时远端 listing 建 base，本地写操作落 delta，远端确认后 fold 进 base。
- `src/cas/commit.*`、`tree_serialize.*`、`object_store.*`：CAS tree + commit + 原子 ref 推进。我们不需要内容寻址存储（内容仍在远端对象存储），但可借鉴“快照 + append-only 历史 + 原子游标”的提交结构。
- `src/cas/inode_map.h/.cpp`：仅是 `(dev, ino, gen) -> path` 的观测索引，并没有提供跨重启稳定身份；对云卷不能直接照搬。云卷的 inode/OID 必须由自己的 metadata store 分配并持久化，作为唯一内部身份。平台对用户展示的文件号只需在各自 adapter 内稳定解析回这个 OID，不要求与 OID 数值相等，也不要求跨平台一致。
- `docs/roadmap.md` L0：先写“durability contract”（明确什么能活过崩溃、什么不能）。这是本计划的第一步，避免先写队列再补语义。
- ContextFS 没有“定期同步到远端对象存储”的层；远端同步器、依赖排序、远端一致性校验需要云卷自己设计。

## 分层设计（提案，按统一元数据缓存重构）

```text
所有读取方（文件管理页面 list/stat、Finder/WebDAV、Linux FUSE、WinFsp、Cloud Files）
        │ 同一个读 API
        ▼
统一 Metadata View（bbolt 持久 B+Tree 为真源 + 可丢弃内存读缓存）
   confirmed tree: 远端最后确认的 inode 父边 / 名称
   desired tree:   本地期望的 inode 父边 / 名称 + tombstone
   OID: 稳定对象身份；path 只在读取时由 inode 边推导
        ▲ 写入方只有一个入口
        │
挂载操作入口(MKCOL/MOVE/PUT close/DELETE)
页面操作入口(createDirectory/upload/rename/delete)
P2P 对账入口 / 远端轮询入口
        │ 先落视图 + journal，再异步远端
        ▼
Journal(seq -> op)  ──►  Remote Sync Worker(定期/静默期/退出前排空)
   inodes: oid -> {desired edge, confirmed edge, content/revision/state}
   journal: seq -> {op, inode IDs, origin, state, retry, batch}
   cursors: local applied seq / remote verified seq / listing cursor
   mkdir -> upload -> rename -> delete 依赖排序
   每步远端执行后验证 HEAD/Listing，再推进 verified seq
```

## inode B+Tree 设计决定（新增，2026-08-17）

### 决定

使用 `bbolt` 作为**持久化 inode B+Tree 的唯一真源**。bbolt 的 bucket/cursor 本身就是磁盘上的 B+Tree，能在一次写事务中同时更新 inode、目录项和 journal；不要再引入一个内存 `google/btree` 作为第二个权威索引。进程内 map/COW 只能是可从 bbolt 重建的读缓存。

元数据数据库不放在用户可清理的 `CacheDirectory`，也不复用 `config.db`：使用 `RuntimeDir()/metadata/v1/<namespace-hash>/metadata.db`。未同步内容的数据面与元数据分离，固定 4 MiB SHA-256 块位于 `<CacheDirectory>/metadata-chunks/<namespace-hash>/chunks/<hash[:2]>/<hash>`；bbolt 的引用计数才是权威。每个 namespace 同时原子发布 `protection.json`，同一次多块暂存必须累积全部尚未提交的 hash；缓存清理读取失败时保守保护全部块，因此 pending 块不会被“清理缓存”删除。

首次创建时把实际 chunk root 写入 schema；后续用户修改 CacheDirectory 也继续读取该根直到显式迁移，避免未同步内容因设置变更而丢失。

`<namespace-hash>` 不能继续使用当前 `safeSegment(bucket)`：它会把不同名字（例如 `a/b` 与 `a_b`）折叠到同一目录，也没有 account/rootPrefix 身份。需要引入不可变 `ProfileID`，并以 `ProfileID + canonical backend identity + bucket + rootPrefix` 派生 namespace；改 display name 或 profile name 不得换库，改变 endpoint/bucket/rootPrefix 则必须显式创建或迁移一个新 namespace。

### bbolt 布局

```text
metadata.db
  schema                 -> {version, namespace, rootInode, nextInode, ...}
  inodes                 -> B+Tree: u64be(inode) -> InodeRecord
  dirents                -> bucket
    u64be(parent inode)  -> 子 B+Tree: nameKey -> Dirent{child inode, displayName}
  journal                -> B+Tree: u64be(seq) -> Operation
  ready_ops              -> B+Tree: state + nextAttempt + seq -> empty
  inode_ops              -> B+Tree: inode + seq -> operation seq
  listing_state          -> prefix inode -> materialization/revision/cursor
  content_refs           -> inode + generation -> PendingContentRef
  chunks                 -> sha256 -> {nlink, size, lastAccess}
```

- root inode 固定为 `1`；其余 inode 通过 bbolt sequence 单调分配，永不复用。对桥接/Dart/Web JSON 暴露时必须编码成字符串，不能把 uint64 当 JSON number 交给 JavaScript 精度处理。
- `dirents/<parent inode>` 是每个目录自己的排序 B+Tree。键为 `nameKey`（挂载可见的比较/冲突键），值保留原始 `displayName`；目录 listing 是对该 bucket cursor 的范围扫描，而不是全路径扫描。
- `InodeRecord` 至少包括：`ID`、`Kind`、`DesiredParentID`、`DesiredName`、`RemoteParentID`、`RemoteName`、`LocalRevision`、`RemoteRevision/Fingerprint`、`State`、`ContentGeneration`、`TombstonedAt`。路径不是权威字段，只能从父边向根回溯按需生成。
- `Desired*` 是本地页面/mount 当前想看到的树；`Remote*` 是远端最后确认的树。目录重命名远端确认后，只更新该目录 inode 的 `RemoteParentID/RemoteName`；所有子孙的远端路径沿父 inode 边推导，**不需要更新任何后代记录**。

### 目录 rename 的事务语义

目录 `A` 从 `oldParent/oldName` 改到 `newParent/newName` 时，一个短 bbolt 写事务完成：

1. 用 `dirents[oldParent].Get(oldNameKey)` 定位 inode，验证预期 revision。
2. 检查目标目录项、跨目录覆盖规则，以及 `newParent` 不是该 inode 的后代（避免 parent cycle）。
3. 从旧父目录 B+Tree 删除旧 dirent，向新父目录 B+Tree 插入新 dirent。
4. 只更新该 inode 的 `DesiredParentID/DesiredName/LocalRevision`，以及旧/新父目录 revision。
5. 在同一事务追加引用 inode 的 `rename` journal 操作和依赖索引。

子目录的 `dirents[child inode]` bucket 继续以 child inode 为键保留，文件内容也按 inode 保存。因此 rename 成本是 `O(log siblings)`，而不是当前 `strings.HasPrefix` 遍历 + 每个后代本地文件 `os.Rename` 的 `O(subtree)`。

远端同步时，操作的 source 用 `Remote*` 父边求值，target 用 `Desired*` 父边求值。若“新建目录 → 本地 rename”发生在第一次同步前，compactor 将其收敛为“在最终 Desired 路径创建”；若目录已存在于远端，则发出一次 remote move。子文件上传仅依赖父 inode 的创建/rename 操作完成，执行时从当前 Desired 树解析目标 key，不做路径字符串 rebase。

### inode 不能解决的边界

- 云端对象存储通常没有稳定 inode。对**本机发起**的 rename，OID 能准确保留身份；对第三方在远端发起的 rename，generic S3/FTP/SFTP/WebDAV 轮询通常只能观察到 delete + create，除非后端提供稳定 provider object ID。默认策略必须是新 OID + 旧 OID tombstone，不能用 size/mtime 猜测身份并误合并用户文件。
- inode/OID 是 metadata store 分配并持久化的内部身份。各平台 adapter 负责保证自己展示的文件号能稳定解析回同一个 OID：Linux FUSE 可直接 `Ino=OID`；WinFsp 可 `FileIndex=OID` 或维护 adapter 内 FileIndex→OID；Cloud Files placeholder FileIdentity 可编码 OID 或用 adapter 查表；macOS WebDAV 的外部 inode 由 webdavfs 生成，云卷只需保证内部对象映射和页面/mount 视图一致。外部文件号不必相等、不必跨平台一致。
- 对大小写不敏感/Unicode 规范化不同的平台，`nameKey` 必须与 `displayName` 分离。远端允许的两个名称可能无法同时投影到 macOS/Windows；这应产生显式 collision/conflict，而不是静默覆盖。

## 远端变化同步与跨设备可见性（新增，2026-08-17）

### 当前实现为什么无法覆盖“双机挂载 + rsync 覆盖同名文件”

以两台机器 A/B 同时挂载同一 bucket 为例，A 上 `rsync` 覆盖已存在的 `dir/file`：

1. A 的 mount 最终会把写入排进 writeback；成功上传后目前只会发送可选 P2P 广播，并由 B 刷新目标的父目录。
2. P2P 默认关闭，且网络发现/投递是优化而不是持久通知；B 离线、P2P 未启用或消息丢失时没有补偿通道。
3. 现有 fallback `remoteDirectoryPoller` 只轮询近期访问的最多 12 个目录；SFTP 更是显式 `SupportsMountRemotePolling() == false`，因此 SFTP 挂载默认没有任何后台远端变化检查。
4. 即便轮询到变化，WebDAV/FUSE/Cloud Files 还必须让已缓存或已水合的同名文件失效。当前依赖 size、mtime、etag 的不同组合；FTP/SFTP 通常只有秒级 mtime+size，无法可靠发现“同大小且同 mtime”的覆盖。

因此，轮询目录 TTL 或 P2P 只能做加速器，不能是跨设备同步正确性的唯一来源。统一 metadata 视图需要一条**可持久补拉的远端 change feed**；同时保留无 feed 时的回源对账降级路径。

### 远端控制平面：不可变事件流，而非共享可变 manifest

对于云卷自己发起且已远端确认的变更，在 bucket 的保留系统前缀（暂定 `.cloud-volume/metadata/v1/`，最终名称必须经过冲突检测和全平台隐藏规则确认）发布不可变事件：

```text
.cloud-volume/metadata/v1/
  devices/<device-id>/head.json              # 最新连续 seq / 可选快照指针
  devices/<device-id>/events/000...001.json  # 不可变、按 seq 排序
  snapshots/<epoch>.json                     # 可选 compaction/bootstrap 快照
```

- 每台设备只写自己的 event stream，避免多个设备并发改同一个 manifest 的 lost update。
- `write` 的发布顺序：本地 pending content durable → 远端对象上传成功并验证 → 写不可变 event → 更新本地 `eventPublished` 游标。崩溃在 event 前时恢复后补发同一个 `operationID`；event 是幂等的。
- event 只记录**canonical remote key/path、源/目标、remote fingerprint、origin deviceID+seq、operationID、可选内容 hash**，不记录本机 inode。inode 是本地 B+Tree 内部 ID，跨机器没有共同含义。
- B 收到 P2P 消息时只把它当作“立即拉取 remote feed/对账”的唤醒信号；B 从 feed 取到 event 后仍需 HEAD/list 验证 remote fingerprint，不能无条件信任广播内容。
- remote feed 不可用（只读、保留前缀冲突、后端不支持所需原子/列表语义）时必须降级为 directory reconciliation，并在 UI/挂载状态中明确标为“仅轮询刷新，不能保证即时跨设备同步”。

### B 收到 A 的 rsync 覆盖后的正确行为

1. A 为原 inode 写入新 `ContentGeneration`，远端确认后发布 `write(path=dir/file, remoteFingerprint=...)` event。
2. B 拉到 event，以 remote path 在自己的 confirmed tree 中解析**自己的** inode；若 B 没有该 inode，则按远端 listing 物化它。
3. B 没有该 inode 的本地 pending 操作时：更新其 `RemoteFingerprint`，使旧 `content_refs` 失效；页面列表显示新的 remote revision，Windows Cloud Files 对该 placeholder 执行 metadata 更新 + dehydrate，WebDAV/Linux FUSE 在下一次读前不再接受旧 content stamp。
4. B 有未同步本地改动时：不覆盖本地 desired content，记录 `conflict(remote changed while local pending)`，展示给页面/挂载状态；用户或策略决定保留两份、覆盖或重试。

这条路径对“同名覆盖”不依赖目录名称变化，也不依赖 size/mtime 恰好不同。内容 hash 或 event `operationID` 作为逻辑版本会让旧缓存失效；下载时再按后端能力验证实际远端版本。

### 外部远端写入与一致性等级

- **通过云卷 mount/UI 写入**：必须发布 remote feed，已挂载的其它设备在 feed poll/P2P 唤醒后获得确定的最终刷新路径。
- **直接在远端或第三方客户端写入**：不会生成云卷 event，只能靠 provider change feed（若有）或 directory reconciliation 发现。
- **S3/WebDAV/FTP/SFTP 的能力差异**：S3 可优先用 ETag/version ID；WebDAV 应补取 ETag/sync-token（若服务端提供）；FTP/SFTP 若只有 mtime+size，则无法数学上保证检测到同 size+同 mtime 的外部覆盖。此类后端需要声明较弱 freshness，或在被标记脏的对象读取时强制下载/校验内容 hash。
- feed retention 被截断或新设备首次加入时：拉取最新 snapshot + 对必要目录回源 listing，不能假设仅靠 event tail 能重建整棵 tree。


## TODO

### M3a lifecycle guard (completed 2026-08-17)

- Mount sessions with an immutable `ProfileID` now retain a `metadata.AcquireHandle` from `newBucketAccess` until their real platform stop path reaches `close()` or `release()`. Missing identities alone keep the legacy fallback; any other metadata-acquire error fails mount startup rather than creating a second read view.
- `AcquireHandle.Release` is idempotent. Shared service policy (`readOnly` and quiet period) and its scoped provider transport are synchronized and refreshed for both `Acquire` variants, so credential, token, or proxy updates affect future materialization/worker operations without interrupting one already in flight. A worker captures its backend once for mutation plus HEAD confirmation. This lets short-lived page handles come and go without closing a namespace held by a mount.
- A pre-registration `CleanupStale`/`Start` failure closes access and metadata normally. The exception is a platform backend that has already left a live mount and rejects cleanup `Stop`: the manager registers that session with an error so a later unmount can retry rather than losing its durable queue.
- The next M3 read batch must still merge metadata only as the remote base: overlay and tombstones before provider materialization, then local files, restored/queued writeback, and directory-marker state. Legacy writes remain outside the metadata journal until M6.

### M3b mount read path (completed 2026-08-17)

- `metadata.Service.ListDirectory(path)` and `RefreshDirectory(path)` hide root inode and page-cursor details from mount adapters. Provider keys are accepted as either directory-relative or view-relative, but deep descendants returned by a malformed one-level listing are rejected instead of being flattened into the wrong directory.
- `bucketAccess.listDirectory`, `statPath`, `ensureLocalFile`, WebDAV/FUSE/WinFsp callers, Cloud Files remote placeholder enumeration/stat, and the bounded remote poller now use that persistent metadata tree whenever the mount has a `ProfileID`. The unscoped mount backend remains only for byte transfer after the metadata path has authorized the object.
- Metadata is the remote base, not an overlay replacement: system overlay and mount-trash handling stay first; legacy tombstones hide both exact paths and descendants; local files, restored writeback records, and directory markers override the base. File/directory collision merging is keyed by normalized path, so `name` and `name/` cannot render twice. Restored durable uploads repopulate their local cache marker before the first read.
- Remote polling re-materializes the persistent directory then gives Cloud Files its metadata-only remote base; placeholder refresh also preserves local directory markers as well as pending writeback and tombstones. Desired+journal writes remain M6 work.

### M5 stable platform identity (completed 2026-08-17)

- Metadata-backed Linux FUSE nodes use their persistent OID for `StableAttr.Ino`; lookup, readdir, and getattr agree. Legacy local-only entries intentionally retain their path-hash fallback until M6 creates their Desired inode.
- WinFsp enables `use_ino`, carries OIDs through cached directory/open-file projections, and publishes them through `Stat_t.Ino`/Explorer's file-index path. The root also resolves to metadata inode 1 when a namespace is available.
- Cloud Files encodes `cloud-volume:v1:<namespace>:<oid>` in `FileIdentity`. Its remote fingerprint is now separate, so a same-OID, same-size ETag/mtime overwrite still updates/dehydrates the placeholder. Poll callbacks preserve OID-bearing metadata objects instead of downcasting them before projection.

### M6a path write facade (completed 2026-08-17)

- `metadata.Service` now exposes `CreateDirectoryPath`, `WritePath`, `RenamePath`, and `DeletePath`, so a caller can make one durable Desired-tree/journal mutation without resolving inode IDs itself. Path-level mutations are ordered; a failed write-journal append releases the just-staged generation rather than leaking protected chunks.
- A zero generation passed to `StageWriteForName` is reserved durably before chunks are staged. Rapid writes of one path therefore retain independent `ContentRef`s and journal generations.
- Re-materializing a provider directory suppresses pending rename sources and tombstones, preventing a stale remote listing from recreating a path the local Desired tree has already removed or moved. Mount/page call sites remain M6b/M6c work.

### M6b mount write integration (completed 2026-08-17)

- Metadata-enabled mount operations now route mkdir, staged file close, rename, and delete through the path facade before success reaches WebDAV/FUSE/WinFsp/Cloud Files callers. The local cache remains a byte/read cache, but it no longer owns the remote mutation; the metadata worker is the only uploader/mover/deleter for that namespace.
- The worker executes writes from their immutable journal parent/name Remote edge, checks an existing fingerprint before mutation, and lets a later rename move that source. Directory rename/delete waits for earlier descendant work, preventing a renamed parent from overtaking its child upload.
- Confirmation keeps an inode `pending` while a later same-inode journal operation remains unfinished, so a refresh between write confirmation and rename execution cannot revive the old Remote key or lose the Desired OID. When a pending rename's destination directory is first materialized, a same-name remote object is ignored unless it matches the inode's confirmed Remote edge; otherwise it could falsely turn the source move into a no-op. Cloud Files rename completion arrives after Explorer has already moved sync-root bytes; its metadata path therefore rebinds the cache marker to the supplied destination instead of attempting a second physical move.
- Before its first provider side effect, a move freezes its actual source/target and confirmation parent/name in the journal. A successful remote move then records a durable `MoveApplied` phase before target confirmation, so a later local rename cannot redirect replay. Restart/retry confirms the frozen target; the narrow remote-success-to-bbolt window probes even generic provider errors and reconciles only when the source is absent and a target fingerprint (or explicit directory marker fingerprint) matches. Missing source and target stays retryable/conflicted rather than being silently accepted.
- Legacy writeback/dir-sync/delete queues remain constructed only for fallback/control compatibility. Metadata-enabled sessions neither restore old records nor enqueue new ones, preventing parallel remote writes. Pending metadata drafts now retain their OID in platform projection.
- Schema v3 marks a path-facade `ContentRef` as awaiting a journal owner. Failed staging/journal append rolls back a newly allocated inode; startup removes an unowned marked ref and its phantom inode after a crash. Raw low-level `StageWrite` stays available for its explicit caller contract.
- **Recorded P2 review risk:** WinFsp currently clears an open handle's `dirty` flag even when metadata staging/journal admission fails during release. The handle close path needs a recoverable retry record before metadata-only sessions can guarantee that failed close is replayable; this is not silently treated as a successful remote mutation.

### M6c page write integration (completed 2026-08-17)

- Profile-scoped page `createDirectory`, `uploadFile`, `renameObject`, `moveObject`, and `deleteObject` now submit the same Desired-tree transaction and durable journal used by metadata-enabled mounts. Admission is local and does not synchronously call the provider; the retained namespace worker performs the remote mutation and confirmation later. A permanent page delete persists `HardDelete`, including across a reopen/replay.
- Page-only handles no longer strand accepted work: `Manager.Release` retains a zero-reference namespace while it has pending/failed operations or pending chunk content, and a later idle acquire/release prunes it. Each page mutation returns a `PathProjection{inode, revision, present}` captured under the path lock; the active mount checks that it is still current before it clears stale markers or adds a tombstone. It deliberately retains source bytes and never calls provider-confirmation callbacks before the worker succeeds.
- Legacy profiles without `ProfileID` retain their direct-provider behavior. Profile-scoped `copyObject` and recursive `uploadDirectory` intentionally fail closed until a durable copy/batch operation can atomically snapshot their complete input; allowing their old direct paths would create a second remote writer.
- **Recorded P2 design gaps:** page task IDs are currently admission IDs rather than worker transfer IDs (`metadata-op-<seq>` remains the worker snapshot). (2026-08-18) The other gap is closed: pending page-upload chunks are now a mount byte-read source — `metadata.Service.ReadPendingRange`/`CopyPendingContent` serve staged chunks before any provider range read, FUSE/WinFsp materialize pending chunks into the ordinary cache file guarded by an inode+generation stamp with singleflight and post-copy revalidation, and Cloud Files cached reads validate the pending generation before reusing a path-keyed cache file. Remaining durable task ownership work is outside the first MVP closure.
- **Recorded P2/P3 review scope:** the browser/Web API transport still performs direct provider mutations when a `ProfileID` exists, so it must be moved to a shared durable adapter (or fail closed for streaming uploads) before it can co-exist safely with a metadata-backed WebDAV session. Desktop page `create`/`rename` inputs also normalize `.`/`..` segments instead of rejecting them at the bridge boundary; keep that low-severity validation fix separate from the durable mutation contract.

### M7 unified reads and acceptance (completed 2026-08-17)

- Profile-scoped `list_object_page`, legacy `list_objects`, and `head_object` now read the persistent namespace first. A metadata manager/acquire failure is returned to the caller rather than silently falling into a mounted-session or provider-direct alternate view. `ListMountedObjectPage` remains only for configs without `ProfileID`, where no durable namespace exists by contract.
- Cross-view acceptance holds one manager handle for a mount and another for a page, then verifies pending mkdir/write/rename/delete are visible immediately through mount list/stat. Reopen-before-worker preserves a pending rename, and forced reset rebuilds an idle namespace from the remote base. Existing rename complexity and crash/replay tests remain the regression anchors.

### M8 unified remote task projection (completed 2026-08-18)

- Schema v4 adds `task_groups`/`task_members`; `Task` IDs are namespace-qualified (`sync:<namespace>:<group>`). The projection folds only deterministic, compatible sequences: unconfirmed mkdir plus renames, consecutive pending renames, and older same-inode writes superseded by a newer generation. Raw journal events remain expandable and folded entries retain every physical `metadata-op-*` reference.
- `list_remote_tasks` and the Web `/api/invoke/list_remote_tasks` route share one JSON contract with profile/bucket/status filters, cursor pagination, `freshness`, and capability flags. Metadata tasks are joined with provider transfer monitor snapshots; sync snapshots carry their profile identity so UI cards use `tasksForProfile()` rather than parsing task IDs.
- Cancellation is transactional for fully pending groups (Desired edges, inode records, and chunk nlinks roll back together). A provider-running cancel is immediately `cancel_requested`, then `reconciling`; it is never shown as completed until a later provider reconciliation proves the outcome. Failed/conflict tasks support retry and pending tasks support trigger without bypassing dependencies. Terminal history is scoped and compacted after 30 days.
- Flutter `RemoteTaskStore` is the only remote-task display source for transfers, sidebar, and file-sync cards. `TransferQueue` remains an execution/local compatibility producer only; endpoint failures surface as freshness errors rather than silently restoring the old list.

## 推荐实施顺序（锁定）

**先完成本地 inode metadata + 页面/mount 统一视图，再做远端同步和跨设备 feed。** 远端 change feed 的 receiver 必须把事件应用到唯一的本地树，才能正确判断“本地 pending”与“远端已变”；在两套缓存并存时先做 feed，只会重新制造 `NotifyExternal*` 式旁路修补。

建议按以下可交付切片推进：

1. **Slice A：持久 inode B+Tree。** 引入 `ProfileID`、metadata namespace、bbolt inode/dirent/journal/content-ref schema，以及 crash/replay/rename complexity 测试。本地是开发环境，现有 `bucketCache`/writeback/JSONL 状态**不做迁移、不保留兼容开关**：新 metadata namespace 直接从远端重建，旧 per-bucket runtime/cache 状态视为一次性开发数据丢弃。
2. **Slice B：统一读取视图。** 页面 `listObjectPage/stat` 与 mount `listDirectory/statPath` 都改读 metadata API；未挂载页面不再直连后端绕过视图。首次目录访问由 metadata service 惰性物化并记录 `listing_state`。开发环境中 metadata 损坏或 schema 不识别时，直接清空 namespace 从远端重建，不做旧格式升级。
3. **Slice C：统一写入入口。** 页面与 mount 的 create/write/rename/delete 均先提交 inode transaction + journal；`NotifyExternal*` 被替换为远端确认后的对账 ingest 入口。此时目录 rename 已不再依赖 `strings.HasPrefix`。
4. **Slice D：journal 驱动的远端同步器。** 最小 inode dependency worker 已落地并负责 metadata-enabled session 的单项上传/move/delete；遗留 writeback/dirSync/mutation/delete 队列仅为无 `ProfileID` fallback 保留。后续再删除 fallback、实现 journal compact 与 durable batch copy；回滚方式是清空本地 metadata 并从远端重建。
5. **Slice E：远端 change feed 与双机对账。** 只有 Slice C/D 后，才能把 A 的 confirmed mutation 发布到 feed，并让 B 可靠应用到自己的统一视图和 mount projection。

Phase 0 的止血修复可以并行落地，但不改变上述主线顺序。

## 第一阶段 MVP 范围（元数据重构 + 页面/mount 统一视图，锁定）

**MVP 定义：** 页面文件管理器与所有平台 mount 的读视图都来自同一个持久 inode metadata service；目录 rename 只改 inode 父边和两个 dirent B+Tree，不再按路径前缀重写缓存。远端仍是真源；本地 metadata 可清空重建；最小单项 journal worker 已随 M6 落地，远端 batch compact 与跨设备 feed 仍不在 MVP 内。

### MVP 必须交付

1. **存储与身份**
   - 不可变 `ProfileID` 存入 profile；namespace = `ProfileID + canonical backend identity + bucket + rootPrefix`。
   - `RuntimeDir()/metadata/v1/<namespace>/metadata.db`（bbolt），schema version、root inode=1、单调 inode allocator；schema 不匹配/损坏时由 reset guard 清空重建。
   - buckets：`inodes`、`dirents[父inode]`、`journal`、`listing_state`、`content_refs`、`chunks`、`ready_ops`、`inode_ops`、`task_groups`、`task_members`。后者驱动 worker 调度、依赖和统一任务投影。

2. **统一读取 API（单入口）**
   - `metadata.Service` 提供 `ListPage(dir inode, cursor)`、`Stat(path)`、`StatInode(inode)`、`Path(inode)`、`ResolveParent(parent, nameKey)`。
   - 惰性物化：首次访问目录时远端 listing → 单事务写入 dirents/inodes → 记录 `listing_state`（directory revision、remote cursor、verifiedAt、remote fingerprint hint）。
   - 分页 cursor 为 `directory inode + directory revision + last nameKey`；revision 变化时返回明确 stale-cursor，页面 reload，不承诺进程内快照一致性。

3. **双端读路径接入**
   - Flutter `listObjectPage/headObject/listObjects`（桌面端）通过 bridge 调 metadata service，不再依赖“该桶是否挂载”的分支；未挂载页面与 mount 返回同一视图。
   - macOS WebDAV `listDirectory/statPath`、Linux FUSE readdir/getattr、Windows WinFsp readdir/stat、Cloud Files placeholder 枚举均读 metadata service。
   - 带 `ProfileID` 的 `ListMountedObjectPage` 会话分支与进程内快照已被 metadata 替换；无身份 legacy fallback 仍保留 `bucketCache`/`localOverlay` 行为。系统临时目录（.Trash/.fseventsd/AppleDouble）不进入 metadata。

4. **inode rename 事务**
   - `Rename(inode, newParent, newName)` 单事务：旧/新 dirent B+Tree 更新 + inode Desired 边更新 + journal append；不遍历子树、不移动子内容文件。
   - 目标覆盖、非空目录覆盖、ancestor cycle、case/Unicode nameKey 冲突返回显式错误。
   - inode/OID 由内部 metadata store 分配并持久化，是唯一身份。各平台只要能把展示的文件号稳定解析回 OID 即可，不强求外部文件号等于 OID：Linux FUSE 建议 `StableAttr.Ino = OID`；WinFsp 可直接用 `FileIndex=OID`，也可在 adapter 内维护 FileIndex→OID；Cloud Files placeholder FileIdentity 可编码 OID 或由 adapter 查表解析；macOS WebDAV 外部 inode 由 webdavfs 生成，属于协议限制，云卷只需保证自己的内部对象映射一致。验收标准是页面与各 mount 呈现同一 Desired/Confirmed 视图，而不是外部 inode 数值一致。
   - mount 侧目录 rename 先更新本地 Desired 树；metadata worker 用冻结的 Remote/Desired 快照执行远端 move，不能反向按路径前缀改写 metadata 的 Desired 树。

5. **写入/失效的最低闭环（不要求 batch 同步器）**
   - mount 与页面写操作在 MVP 中必须同步写 metadata Desired 状态（create/mkdir/rename/delete/write 至少更新视图与 journal 记录），避免读视图出现旧路径幽灵条目。
   - metadata worker 的远端确认路径更新 Remote 边/fingerprint/verified 状态；不删除仍有 pending journal 的内容。
   - remote listing 对账：页面强制刷新与打开目录时按 `listing_state` 重新拉取并合并 dirents；MVP 不要求后台全量同步。

6. **平台一致性投影（最低集）**
   - Windows Cloud Files：远端 listing 刷新后 placeholder create/update/dehydrate 继续可用，路径解析改为先查 metadata inode。
   - Linux FUSE：rename 后 readdir/getattr 使用新 Desired 边；短 entry/attr TTL 保持现状。
   - macOS WebDAV：Finder rename/列举由 metadata 视图服务；仍需通过现有远端路径完成实际数据写回。

7. **可观测性与验收**
   - bridge 暴露 metadata 状态：namespace、schema version、inode count、listing materialized count、stale cursor/rebuild 次数。
   - 开发诊断命令：清空 namespace 重建；重建前 reset guard 检查 pending journal。
   - 验收测试：
     - 页面与 macOS WebDAV（及可用平台的 FUSE/WinFsp）读取同一目录得到同一集合（含 pending/tombstone）。
     - 未挂载时页面浏览/分页不回落到直连远端分支。
     - 100 万子项目录 rename 只触碰 inode + 两个 dirent bucket（断言不扫描子树）。
     - rename 后页面与 mount 立即看到新路径；重启后视图从持久 metadata 恢复；清空重建后与远端一致。
     - `go test ./...`、`flutter analyze` 全绿。

### MVP 明确不做

- journal compact、批量 copy/递归目录上传等完整同步器能力（Slice D 后续）。
- 远端 immutable change feed、P2P 协议升级、双机离线补拉（Slice E）。
- 旧 writeback/mutation JSONL 迁移、feature flag、A/B 校验。
- trash 全量统一（保留现有 trash 视图，但 mount 隐藏逻辑可读取 metadata 树；完整 trash 归并后续做）。
- 冲突解决 UI 与跨设备版本策略。

### MVP 推荐实现批次

1. **M1 存储核心**：ProfileID、namespace registry、bbolt schema、inode allocator、dirent B+Tree、事务 API、reset guard、单元测试。
2. **M2 物化与读 API**：远端 listing ingest、listing_state、ListPage/Stat/Path、stale cursor、分页 API。
3. **M3 mount 读接入（已完成）**：WebDAV/FUSE/WinFsp/Cloud Files readdir/stat 全部改读 metadata；本地 overlay 保持旁路，轮询刷新同一持久远端基底。
4. **M4 页面读接入（已完成）**：bridge list/stat 改走 metadata；有持久身份的页面不再走 `ListMountedObjectPage` 会话分支；页面分页适配 stale cursor。
5. **M5 rename 事务与内部身份关联（已完成）**：inode rename；各平台 adapter 保证 metadata-backed 项的展示文件号能稳定解析回 OID（Linux FUSE 直接用 `Ino=OID`，WinFsp/Cloud Files 直用 OID，macOS WebDAV 保持内部映射）。
6. **M6 写入口最小同步（已完成）**：M6a facade、M6b mount 写入口和 M6c 页面 create/upload/rename/move/delete 已接入 Desired+journal；worker 的确认事务更新 Remote 边。复杂 copy/递归目录上传在有持久身份时 fail-closed，等待专门的 durable batch op。
7. **M7 一致性与验收（已完成）**：双端视图一致性、rename crash/replay、重开和 reset rebuild 覆盖已补齐；提交前执行全量 `go test ./...` + `flutter analyze`。
8. **M8 统一远端任务投影（已完成 2026-08-18）**：journal task groups/controls、desktop/Web JSON API、物理传输 adapter、RemoteTaskStore 与任务页/侧栏/同步卡片切换完成；旧 TransferQueue 不再作为展示 fallback。

### Phase 0 — 先止血（不依赖新架构）

- [x] 修复 `writeback_restore.canRestoreRecord`：本地缓存默认在 `~/.cloud-volume/cache/mounts/<bucket>`，不在 sessionRoot 内；恢复时应同时接受 sessionRoot 与 cacheRoot，否则重启即丢上传。
- [x] macOS `mountSession.stop` 在卸载前调用 `drainWriteback()`，与 Linux FUSE / WinFsp 对齐，并给 drain 设置用户可见超时结果。
- [x] `renamePath` 也调用 `dirSync.rebaseAndFence`，避免“未命名文件夹” marker 在重命名后仍按旧名建到远端。
- [x] `dirSync.flush` 失败进入可观测 error 状态，通过 mount `LastError` 和桶操作旁提示展示；失败仍会结束 fence，避免卡住后续写回。
- [x] 修正 `InvalidateExternalUpload` 直接 `removeLocalPath`（连带删本地缓存文件）的行为：仅当该路径没有 pending writeback 时才清理，避免页面覆盖上传误删 mount 本地数据。
- [x] 写 durability contract 文档：明确 quit / crash / unmount 三种场景下哪些状态承诺恢复。

#### Phase 0 durability contract (2026-08-17)

- **Quit / requested unmount (macOS):** the session drains persisted file writeback before it asks macOS to unmount the WebDAV volume. The wait is bounded by the configured transfer timeout. A timeout or upload error leaves the volume, WebDAV server, queue, and persisted records live, returns a user-visible failure, and allows a retry; it never silently closes the queue.
- **Crash / forced termination:** file writeback records survive under `runtime/mounts/<bucket>/writeback`, and a remount restores a record only when its source is still a regular file inside either `sessionRoot` or the configured `cacheRoot`. Every new writeback/mutation record is bound to `ProfileID + provider + endpoint + bucket + RootPrefix + provider principal` (S3 access key, WebDAV username, FTP/SFTP username+port, or Baidu refresh token); a mismatched (including legacy unscoped or older scope-format) record remains dormant in the queue store rather than being replayed into another remote or discarded during compaction. Directory-marker creates remain memory-only.
- **Rename versus writeback:** a synchronous mount rename holds the common path gate, drains queued and running writes for its source path/subtree, then sends the remote move under the remote-mutation mutex. Only after the destination remote postcondition succeeds are pending/not-yet-started delete targets rebased; a failed move leaves delete intent at its source. New mkdir/delete requests block until that ordering is fixed. Cache files are moved before cache indexes and queue records change; a failed physical move leaves the source queue record intact rather than turning the next flush into a false `flush-missing` success.
- **External page mutation while mounted:** an upload/create invalidates remote lookup caches, but keeps a matching pending writeback file and its local marker. The local marker is also protected during the writable-handle-before-close window; a settled local cache entry remains evictable by that invalidation.
- **Directory marker failures:** the most recent failed `CreateDirectory` is process-local mount status, clears after a later successful create of that path, and is intentionally neither persisted nor retried by Phase 0. Fences still complete on failure so one marker cannot block the whole bucket.

### Phase 1 — 统一元数据存储核心（页面与 mount 共用）

- [x] 新建 `go/mount/metadata` 包，选 bbolt（已有依赖）而非新增 SQLite；存储生命周期与 mount session 解耦（按稳定 `ProfileID+backend+bucket+rootPrefix` namespace 常驻，不随 unmount 销毁）。
- [x] 给 profile 存储引入不可变 `ProfileID`，并定义 metadata namespace registry；Flutter config JSON 同步保留该 identity，`DefaultManager` 为进程级共享实例。禁止用 `safeSegment(bucket)` 作为 metadata DB 身份；开发环境不迁移旧 namespace，直接重建。
- [x] 创建独立的 `RuntimeDir()/metadata/v1/<namespace-hash>/metadata.db`；不要放到 `CacheDirectory` 或 `config.db`。定义 schema version、root inode=1、单调且永不复用的 uint64 inode allocator；schema 不匹配或 db 损坏时删除重建，不写旧格式升级路径。
- [x] 落地 bbolt inode B+Tree：`inodes[inode]`、每目录 `dirents[parent inode][nameKey] -> child inode`、`journal[seq]`、`ready_ops`、`inode_ops`、`listing_state`、`content_refs`。所有键使用固定二进制编码，避免字符串拼接/前缀歧义。
- [x] 数据结构（MVP 不含 symlink/rmdir）：
  - `Inode{ID, Kind(file/dir/symlink), DesiredParentID, DesiredName, RemoteParentID, RemoteName, Size, MTime, LocalRevision, RemoteFingerprint, State(local-only/pending/synced/conflict/tombstone), ContentGeneration}`
  - `Dirent{ChildID, DisplayName, NameKey}`，同一目录的 dirent 存在该目录自己的 bbolt B+Tree 中。
   - `Op{Seq, TaskGroupID, Type(create/write/rename/mkdir/rmdir/delete), InodeID, ParentInodeIDs, ExpectedLocalRevision, ExpectedRemoteFingerprint, Origin(ui/mount/p2p/reconcile), State(pending/running/verifying/failed/applied/cancel_requested/reconciling/canceled), Retry, LastError}`；路径只能作为审计快照，不作为执行真源。
  - `Op.Write` 额外固定 `ContentGeneration`，执行时只能读取该 generation 的块列表；连续写同一 inode 时每个操作独立上传/retire，不能回读 inode 当前 generation。
  - `ListingCursor{DirectoryInodeID, DirectoryRevision, LastNameKey, RemoteCursor, VerifiedAt, RemoteRevHint}`。
- [x] 单事务保证：本地视图变更 + journal append 原子提交。
- [x] 实现 `Rename(inode, destinationParent, destinationName)` 单事务：两个 dirent B+Tree 更新 + 一个 inode 边更新 + journal append；不枚举子孙 inode，不移动子孙内容文件。实现目标覆盖、非空目录、ancestor cycle、case/Unicode collision 的明确错误语义。
- [x] 内容持久化协议（2026-08-17）：写入按固定 4 MiB 分块、SHA-256 内容寻址；块先 fsync + 原子 rename 到 cache root，再提交 `ContentRef{chunks[]}` 与 `chunks[hash].nlink++`。上传时临时拼接完整文件；确认/删除后 `nlink--`，归零删块。启动 sweep 清除孤儿块和中断的拼接临时文件；仅已 StageWrite 的内容以及 pending/running/failed journal 均计入 reset guard。
- [x] 缓存挂钩（2026-08-17）：缓存统计显示 protected pending 块；按规则清理与清空缓存都跳过 `protection.json` 标记的 pending 块，清单缺失或损坏时保护整个 namespace。已同步读缓存尚未迁移到块存储。
- [ ] journal append-only；verified seq 之后才允许 compact。
- [x] 读 API 同时覆盖页面分页与 mount readdir/stat：`ListPage(prefix, cursor)`、`Stat(path)`、`GetOID(oid)`；有 `profileId` 的 `list_object_page` / `list_objects` / `head_object` 和 mount readdir/stat 都走 metadata，无身份才保留 legacy fallback。
- [x] 将分页 cursor 改为 `directory inode + directory revision + last nameKey`；若目录 revision 已变，返回明确 stale-cursor 错误给页面 reload，不保留当前进程内 2 分钟快照作为一致性承诺。
- [ ] 冷启动策略：根目录优先惰性物化，后台按需拉子目录；大桶不阻塞首屏，同时 UI 标注“未完全物化”。
- [ ] 单元测试：崩溃后重放 journal、OID rename 后路径索引更新、tombstone、compact 幂等、页面与 mount 读同一份 delta；断言百万子项目录 rename 只触碰 inode/两个 dirent bucket，不扫描子树。

### Phase 2 — 双入口改造：mount 与页面走同一写路径

- [x] `createDirectory/renamePath/deletePath/scheduleUpload` 在 metadata-enabled mount 中先写 metadata+journal，再返回成功给 Finder/FUSE；未持久化 ProfileID 的 fallback mount 保留 legacy queue。
- [x] 页面 `createDirectory/uploadFile/renameObject/deleteObject` 改为同一 journal 入口（先视图后远端），替代“远端成功 + NotifyExternal*”的反向修补；metadata 分支由 worker confirmation 更新 Remote 边，挂载只做不删字节的 Desired 投影。
- [ ] `NotifyExternal*` 被替换为远端确认 ingest 入口：只按远端 fingerprint 合并 confirmed 状态，不得删除仍 pending 的本地内容。
- [ ] 为每个对象分配稳定 uint64 OID；journal 的 rename 只改 DesiredParentID/DesiredName，不改 OID，且不重写任意 descendant。
- [ ] 各平台展示文件号能稳定解析回内部 OID：Linux FUSE `linuxFuseStableAttr.Ino` 建议直接等于 OID（替换 path hash）；WinFsp `FileIndex` 可直接返回 OID 或在 adapter 内维护解析表；Cloud Files placeholder FileIdentity 可编码 OID 或由 adapter 解析（不再用 `path+ETag` 作为主身份）。watcher `MarkRenameSource/Rebase` 改为按 OID 追踪。外部文件号不要求跨平台相等。
- [ ] macOS WebDAV 说明限制：对外 inode 由 webdavfs 生成，本地只保证内部 OID 稳定。
- [ ] 把写入内容缓存从当前 `pathForVirtualKey(cacheRoot, virtualPath)` 改为 inode/generation 目录；目录 rename 不得调用按子树的本地文件移动。
- [ ] trash 统一：页面 trash 视图与 mount 隐藏逻辑共享同一棵元数据树 + trash 标记，`listTrashPage` 不再是独立后端世界。
- [ ] 删除旧 writeback/dirSync/mutation/delete 队列路径，不做 A/B 并行校验；开发环境回滚 = 清空本地 metadata namespace 并从远端 listing 重建。


### Phase 3 — 远端同步器

- [ ] 同步调度：静默期 + 定时 + 退出前强制 drain；输入是 journal 而非内存队列。
- [ ] 用 inode 依赖图排序：父目录 marker 先建；同 OID 的 write 后 rename 不重复上传；只阻塞依赖该父 inode 的后代操作，rename 失败不阻塞整个 bucket。
- [ ] remote source 一律由 `RemoteParentID/RemoteName` 边推导，remote target 一律由 `DesiredParentID/DesiredName` 边推导；禁止在 worker 中以字符串前缀 rebase 排队操作。
- [ ] 本地新建目录在第一次远端确认前若发生多次 rename，compact 为一次最终 Desired 路径的 mkdir；已远端确认目录则生成一次由 Remote 树到 Desired 树的 move。远端 move 成功后只更新该 inode 的 Remote 边。
- [ ] 子文件 upload 的 target 在执行时从 Desired inode 树解析；若祖先有未完成 create/rename，则仅建立精确 inode dependency，不复制或重写子操作的路径。
- [ ] 后端能力差异处理：SFTP/FTP 自动建父目录，S3 平 key，WebDAV 需显式 MKCOL 父链。
- [ ] 每个远端操作执行后 HEAD/Listing 验证，验证成功才推进 verified seq。
- [ ] 为每个后端实现 `RemoteFingerprint` 能力：优先 version ID/ETag，其次高精度 mtime+size；明确 FTP/SFTP metadata-only 指纹不能识别同 size+同 mtime 覆盖的限制。
- [ ] 为 pending content 计算可选 SHA-256（或可配置内容哈希），在远端确认后的 event 中记录逻辑版本；对无 ETag 后端用它避免把旧本地缓存误判为新版本。
- [ ] 冲突策略：远端在 pending 期间被外部修改 → 记录 conflict，不自动覆盖；UI 提供覆盖/保留两份。
- [ ] 重试退避与死信：连续失败进入 failed，可见且可手动重试，不再无限 `mutation state conflict`。

### Phase 3.5 — 远端 Metadata Change Feed（跨设备正确性）

- [ ] 定义保留远端系统前缀、冲突探测、隐藏规则与权限预检；页面、WebDAV/FUSE、Windows Cloud Files 都不得把该前缀作为用户文件投影。若用户已有同名前缀，必须停止启用 feed 并给出迁移/改名路径，不能静默覆盖。
- [ ] 定义 v1 event schema：`operationID`、`originDeviceID`、单设备单调 `seq`、scope identity、type、canonical source/target key、remote fingerprint、可选 content hash、timestamp；**禁止传本机 inode 作为跨设备 identity**。
- [ ] 建立 per-device immutable event stream + `head`，而不是一个多写者共享 manifest；实现 event publish 的恢复、幂等、签名/HMAC 或同等完整性校验。
- [ ] remote object mutation 已 HEAD/list 验证后才 publish event；若发布失败，journal 保持 `remote-confirmed/event-unpublished` 并后台补发，不允许提前对外宣布成功。
- [ ] 所有已挂载 bucket 低成本轮询 remote feed head；P2P 只用于立即唤醒，不作为唯一传播通道。设备离线后从 durable feed cursor 补拉。
- [ ] receiver 逻辑：event → HEAD/list 验证 → 用 canonical path 解析本机 inode → 更新 confirmed tree/remote fingerprint → 无 pending 时使 content ref 失效并更新平台投影；有 pending 时进入 conflict。
- [ ] feed retention/compaction：每个设备维护 ack/cursor，高水位生成 bootstrap snapshot；新设备或 cursor 落后于 retention 时 snapshot + directory scan 重建。
- [ ] 后端 capability gate：S3/WebDAV/FTP/SFTP 都测试保留前缀的 create/list/read/atomic publish；不满足时显式落到 polling-only 模式并暴露 freshness 等级。

### Phase 4 — 重启、对账与远端变化进入视图

- [ ] 启动流程：打开 bbolt → 重放未 verified journal → 校验本地内容文件仍存在（cacheRoot 内）。
- [ ] 远端 listing 对账：只比对 cursor 之后的变更；用 WorkingTree base/delta 思路，base 来自远端 listing，delta 来自 journal。
- [ ] 页面直连远端操作（Web / 无本地视图模式）在视图存在时也走 journal；视图不存在时明确降级为“远端直连 + 下次启动对账”。
- [ ] P2P 事件、remote change feed 与远端轮询统一走同一对账入口；P2P 广播保留 canonical path + remote fingerprint + origin sequence，接收端将其解析为自己的本地 inode，不能把一个设备的 inode 传给另一个设备。
- [ ] 轮询策略重做：不能只依赖最近访问的 12 个目录。feed 已启用时轮询小型 head/event；feed 不可用时维护持久化的 watched/materialized directory 集合、刷新 SLO 和后端连接预算，SFTP 不能再默默禁用所有跨设备刷新。
- [ ] 对已缓存/已水合内容的失效统一为 metadata 操作：content stamp/fingerprint 不匹配时删除或弃用 content ref；Windows Cloud Files dehydrate placeholder，Linux FUSE 做 inode/entry invalidation 或在短 TTL 后拒绝旧缓存，macOS WebDAV 通过下一次读强制重新校验。
- [ ] 分页 token 重定义：持久 listing cursor + 变更版本号，替换进程内 `m:<id>:<offset>` 快照 token；明确不一致窗口的 UI 表现。
- [ ] journal compact 规则：同一 OID 的 create→rename→write 可折叠为一个 pending create；不可折叠的 delete/rename 顺序保留。
- [ ] 本地状态重建与丢弃策略：metadata 损坏或 schema 不识别时删除 namespace、content-addressed chunk refs 与 cache stamp 后从远端重建；开发环境不为旧 writeback/mutation JSONL 写导入器，明确“未同步内容可能丢失”的开发期约束。

### Phase 5 — 平台与 UI

- [ ] 挂载状态页显示 metadata store 健康度、pending ops 数、最后 verified seq/time、视图物化进度。
- [x] 传输页把 dir marker、rename、delete、sync 和应用更新投影为统一 `RemoteTask`；主列表按有效操作展示，raw journal/physical phases 可展开，支持取消/重试/立即执行与历史清理。
- [x] 任务 API 提供 namespace-qualified IDs、依赖原因、cursor 分页、freshness/capability 字段；Web 按认证 active profile 限制范围。
- [ ] Windows Cloud Files sync state 投影到新 journal 状态；WinFsp placeholder 状态同步投影。
- [ ] P2P mutation 广播改为携带 canonical remote path + remote fingerprint + origin device sequence；OID 只在本机 metadata store 内使用。
- [ ] 页面显示远端 freshness：最后 feed cursor、最后远端验证时间、polling-only/fresh/conflict 状态；在 backend 无可靠外部变化检测时明确提示，而不是显示“已同步”造成误解。
- [ ] 页面与 mount 的可见性验收：同一路径在页面列表、Finder/FUSE、Explorer 中显示一致（含 pending/tombstone 状态）。

### Phase 6 — 压测与验收

- [ ] 回归场景：新建目录立即重命名 → 上传文件 → 10 秒静默期内退出 → 重启，远端最终一致。
- [ ] 页面操作与 mount 操作交错：页面上传覆盖 mount pending 文件、页面 rename 挂载中目录、mount rename 后页面立刻刷新。
- [ ] 双机回归：A/B 同时挂载；A 上 `rsync` 覆盖既有同名文件（分别覆盖为不同 size、同 size 不同 mtime、同 size 同 mtime）；A remote-confirmed event 发布后，B 在 P2P 开启/关闭、离线后重连、SFTP polling-only 三种条件下都按声明的 freshness 级别更新或明确报告无法验证。
- [ ] 双机冲突：A/B 分别离线修改同一 inode，重连后不覆盖任一 pending content，双方进入可恢复 conflict 状态。
- [ ] 大目录 rename + 并发上传；断网中途 rename；远端目录被外部删除；同 OID 多次 rename。
- [ ] 大桶冷启动（≥100k entries）页面首屏与目录展开性能基准；bbolt 打开/lookup/compact 基准。
- [ ] `go test ./...` + `flutter analyze` 全绿后提交。


## 关键取舍

- bbolt vs SQLite：bbolt 已在 config/cache index 使用，无 CGO、事务模型够用；SQL 查询能力对本场景不是刚需。
- 本地 metadata 可丢弃性：开发环境不做旧状态迁移和兼容开关。远端 listing 是重建真源；清空/重建是 schema 变更与故障恢复的默认手段。未来正式发布前再评估是否需要保留 pending 数据的升级路径。
- inode 由内部维护：OID 由我们自己的 metadata store 分配并持久化。平台展示的文件号只需由 adapter 稳定解析回同一 OID（Linux FUSE/WinFsp 常直接复用，Cloud Files 可编码或查表，macOS WebDAV 外部 inode 例外）；验收标准是页面与 mount 视图一致，而非外部 inode 数值一致。
- inode scope：inode/OID 是**每台设备本地 metadata store 的稳定身份**，不是跨机器协议字段；跨设备只交换 canonical remote key、remote fingerprint 和 durable operation/event ID。
- 视图生命周期：metadata store 按 profile+bucket+rootPrefix 常驻，与是否挂载无关；mount session 只是视图的一个投影端。这是“页面和 mount 统一用这个视图”的前提。
- 页面写顺序：放弃“远端成功后再通知挂载”的反向修补模式，统一为“视图+journal 先行、远端异步验证”；Web 场景保留远端直连并显式声明降级语义。
- 跨设备发现：P2P 只加速通知；远端 immutable change feed 才提供离线可补拉的应用自有变更历史。无法启用 feed 的后端必须明确是 polling-only，不能承诺即时同步。
- 先写本地再同步远端：这是解决本次故障的核心，否则任何队列仍然会在退出/崩溃时丢状态。
