# Agent Note: journal-first 持久元数据核心统一挂载与页面视图

Status: implemented

## Problem

挂载(Finder/WebDAV/FUSE/WinFsp/Cloud Files)与 Flutter 文件管理页各自维护读路径:挂载读本地缓存桶视图,页面直接列 provider,同一远端的两侧视图可以不一致;写回靠四个协作队列(内存态目录创建、无原子性的 JSON store、缺/缺状态无限重试的 mutation reconciler),崩溃后的恢复语义薄弱且跨平台各自维护。设计与分期计划见 [MountMetadataJournalPlan.md](../../../MountMetadataJournalPlan.md)。

## Decision

一个持久 inode B+Tree(bbolt)+ 操作 journal 构成**单一事实来源**,挂载与页面共享:

- `metadata.Service`(`go/mount/metadata/`)持有 inode/dirent/journal/content_refs;`Manager.Acquire`(注入/测试变体 `AcquireWithBackend`)是获得句柄的唯一入口,命名空间按 `ProfileID + storageType + endpoint + config bucket + rootPrefix + bucket` 稳定派生。
- 写路径全部 journal-first:mutation 先提交 journal(`ready_ops`)再触达 provider;worker 串行 claim/execute,带重试退避、依赖谓词、静默屏障与基于探测的取消对账。
- chunk 内容寻址(SHA-256、fsync + 原子重命名后进 bbolt、`nlink` 引用计数),保护 manifest 是缓存清理唯一权威。
- 本地 metadata 定位为**可重建缓存**:schema 不匹配/损坏即删除并从远端 listing 重建,无原地升级;pending(未同步到远端)内容是唯一数据级状态,受 reset guard 保护。
- 旧四队列体系降级为无 `ProfileID` 配置的回退路径;有身份的挂载只把它当惰性控制面。现行契约全文见 [mount_metadata_core](../../../features/mount_metadata_core.md)。

## Alternatives considered

- **继续修补 legacy 四队列** — 输在双写者风险(挂载与页面两个独立远端写者)与持久化强度:目录创建不落盘、队列 JSON 无原子写,修到等价要重写的东西比重写本身还多。
- **迁移旧 writeback/mutation JSONL 到新存储** — 开发期成本高且只服务历史数据;决定不迁移,旧记录按 scope 休眠保留,回原 profile 仍可用。
- **跨设备直接同步本地 OID** — 每设备本地分配的 inode 号不可跨设备对齐;跨设备同步改为设计中的远端不可变事件 feed(规范远端路径 + 远端指纹 + origin 序列),当前由 P0 轮询与 P2P 兜底。

## Consequences

- 页面/挂载同源可被测试钉死:`go/mount/metadata_shared_view_test.go` 证明两侧句柄看到同一 Desired 视图;`mvp_recovery_test.go` 钉住重开与强制重建。
- 没有升级路径成为明确契约:schema bump 即重建,换来存储层永久简单;reset guard 把"误删 pending 数据"从操作风险提升为代码级禁令。
- 代价与遗留:legacy 队列仍需维护(回退路径未删除);Web API 上传在 `ProfileID` 存在时仍 provider-direct(M6c 已知 P2);跨设备新鲜度在事件 feed 落地前不完全。
- 顺序是 binding 的:store → 统一读 → 公共写入口 → journal worker → 跨设备 feed,不允许跳步(见 [mount_metadata_core 的范围与阶段约束](../../../features/mount_metadata_core.md#范围与阶段约束))。
