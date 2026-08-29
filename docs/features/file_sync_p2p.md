# File Sync & LAN P2P — 文件同步与局域网点对点

## 文件同步(文件同步)

用户可把本地目录绑定到远端桶前缀并按计划同步(上传/下载/双向),带冲突策略与排除规则。Go 侧跑调度器计算 diff 并执行;Flutter 侧管理配置并显示实时状态。同步配置管理已完全从设置页迁到文件同步任务页(设置页无「文件同步」tab);任务页是创建、编辑、删除、开关、触发同步配置的**唯一**入口。

### Flutter 文件

- `lib/pages/file_sync_tasks_page.dart` — 任务页,**同步配置唯一管理中枢**。摘要卡 + 配置行;完整 `sync_*` 队列在传输页;每个配置卡经 `file_sync_profile_active_task.dart` 显示最新 pending/running 任务。
- `lib/pages/file_sync_tasks_page_actions.dart` — part 文件,CRUD 扩展(`_FileSyncTasksActions`):`_addProfile`、`_editProfile`、`_saveProfile`、`_deleteProfile`、`_toggleEnabled`、`_triggerSync`。拆分保持页面 500 行内。
- `lib/widgets/file_sync_profile_editor.dart` — 创建/编辑单个 `SyncProfile` 的编辑器。**两步向导:** step 1 同步两端(可选名称、本地目录 `FilePicker`、远端目录 `RemoteDirectoryPickerDialog`),step 2 同步策略(方向、冲突策略、间隔、静默期、排除规则、启用开关)。接收 `api` + `List<FileManagerBucketEntry> buckets`。**`asDialog`:** `true`(默认)为**默认应用内模态**包 `ShadDialog`;`false` 仅返回裸 `_buildContent` 给 debug OS 子窗口——**绝不在分离子窗口内嵌套 ShadDialog**。子窗口布局 `_buildSubWindowLayout`:固定步骤指示 + 可滚动步骤体 + 固定导航按钮(避免 step 2 RenderFlex 溢出)。保存成功:`onSaved` 后仅 `asDialog` 为 true 时 `Navigator.pop`。
- Debug 子窗口栈(保留非默认):`lib/models/sync_editor_window_args.dart`(args:profileNames + 可选 initialProfileJson)、`lib/app/sync_editor_window_app.dart`(共享 `DesktopModalSubWindowApp(scrollable: false)`,bootstrap 载桥接 + 桶列表,内容 `FileSyncProfileEditor(asDialog: false)`)、`lib/services/sync_editor_window_service.dart`(+`_io`/`_web`;`isSupported` 跟随 `preferModalSubWindows`,false 时 `openEditor` 返回 false,页面走 `showAppModal`)。呈现策略与共享组件见 [app_modal](app_modal.md)。
- `lib/widgets/remote_directory_picker_dialog.dart` — 文件管理式远端目录选择器。`showRemoteDirectoryPicker` 用 `showDesktopOverlayOrDialog`(默认应用内模态)。支持 `asDialog`、`onConfirm`、`onCancel`,返回 `RemoteDirectoryResult(bucket, prefix, profileName, config)`。
- `lib/widgets/remote_directory_picker_list.dart` — part 文件:目录列表 + **仅展示的文件行**。目录与 `..` 可选;**文件不可选**(`FileListTile` `dimmed: true`)。「显示隐藏文件」开关过滤点前缀名。文件图标用**灰度 `ColorFilter.matrix`**(不是 `srcATop` tint)使多色 SVG(如 zip)正确变灰;标题/尺寸用 muted 文字。
- `lib/widgets/file_list_tile.dart` — 共享列表行;`dimmed` 禁用 hover/press,用箭头(非手型)光标,muted 前景绘制标题/尺寸。`FileListTile` idle 保持 `SystemMouseCursors.basic`,仅自身 `_hovered` 为 true 时切 `SystemMouseCursors.click`(回归曾让所有非 dimmed 行 `cursor: click`,预览/打开交互后光标残留手型);`deleting` 行同样按非交互处理。
- `lib/widgets/remote_directory_picker_actions.dart` — picker 的 `_loadObjects` / `_createDirectory`。
- `lib/widgets/file_sync_profile_editor_steps.dart` — part 文件,顶层函数 `stepPickEndpoints`、`stepSyncStrategy` 与桶 tile/list 辅助;接收 `_FileSyncProfileEditorState self` 调 `self.markDirty(...)`。
- `lib/models/sync_profile.dart` — 数据模型:`SyncDirection`(upload/download/twoway)、`SyncConflictPolicy`(newest/localWins/remoteWins/skip)、`SyncProfileStatus`(idle/syncing/error/paused)、`SyncProfile`(镜像 `go/sync/profile.go`)、`SyncProfileRuntime`;均有 `fromJson`/`toJson`/`copyWith`。
- `lib/state/sync_profile_notifier.dart` — 单例 `SyncProfileNotifier`(ChangeNotifier),每 3 秒轮询 Go 运行时状态;暴露 `profiles`、`saveProfile`、`deleteProfile`、`triggerProfile`。任务页是唯一 UI 监听者。

### 删除检测与同步(对账模型)

**远端扫描深度(binding):** `go/sync/reconcile.go` `scanRemote` 必须列出 `RemotePrefix` 下**全部嵌套文件**,不只是即时 listing 页。文件管理 `ListObjectsPage` 用 delimiter/depth-1 供 UI 浏览;同步用 `storage.Backend.ListObjectsRecursive`(S3:无 delimiter 分页器;WebDAV:PROPFIND depth infinity;百度:目录 BFS)。同步若只见顶层文件,空本地 + 含子文件夹的远端树在双向同步下也产出**零下载**。

**本地目录 key:** `scanLocal` 只走文件,`classify` 调 `localDirSide` 检测已存在文件夹。否则 `ensure_local_dir` 索引条目会让下一遍把远端目录当已消失并对文件夹路径发 `delete_local`。

**空远端目录:** 远端有目录标记(S3 `key/` 占位、WebDAV/百度 `IsDir`)而本地缺失时,同步也发 `OpEnsureLocalDir`(`sync_mkdir`)。只对账文件不会在无文件的远端目录建文件夹。

每次对账对每个相对路径比较**三个视图**:本地扫描(`localSide`)、前缀下远端列表(`remoteSide`)、**持久索引**(bbolt `IndexEntry`——上次同步的本地/远端 size+mtime)。key 是三集合之并(`go/sync/diff.go` `classify`)。

**「删除」在一侧现已缺失但索引记录该侧曾存在时推断:**

| 现状 | 索引提示 | 方向 | 操作 |
|-----|------------|-----------|-----|
| 本地缺,远端有文件 | `idx.LocalSize` 或 `idx.LocalMTime` ≠ 0 | 双向 | `delete_remote`(本地删除传播到桶) |
| 同 | 同 | 仅上传 | 跳过 |
| 同 | 同 | 仅下载 | `download`(`local_deleted_redownload`,当本地丢失从远端恢复) |
| 本地有文件,远端缺 | `idx.RemoteSize` 或 `idx.RemoteMTime` ≠ 0 | 双向 | `delete_local` |
| 同 | 同 | 仅下载 | 跳过 |
| 同 | 同 | 仅上传 | `upload`(`remote_deleted_reupload`) |

两侧都缺但仍在索引 → `skip`(`stale_index`)。仅一侧全新文件(索引从无另一侧)→ 常规 `upload`/`download`,不是删除。

**重命名 vs 删除:** classify 后,`reconcile.aggregateRenames` 把 pending delete 与等大小 add 配对(仅双向)→ `OpRename` 代替删除+上传(`go/sync/rename_detect.go`)。

**执行:** `OpDeleteRemote` → `backend.DeleteObject`;`OpDeleteLocal` → `os.Remove`。队列 kind `sync_delete`。成功后该相对路径索引条目**移除**(`executor.updateIndex`)。涉及本地路径的删除可被静默期推迟(仅 upload/rename/delete_local 的 `runner.isHot` 热文件检查)——仅远端删除不受静默期约束。

**非实时 FS watch:** 周期对账(`intervalSeconds`)+ 手动触发;不是 inotify 式即时删除同步。

### Go 文件

`go/sync/profile.go`(结构/JSON,Go 侧 `SyncProfile` 唯一真源)、`store.go`(持久化)、`scheduler.go`(按 `intervalSeconds`/`quietSeconds` 周期触发)、`runner.go`(单次同步编排)、`diff.go`(diff 计算操作集)、`reconcile.go`(冲突策略处理)、`executor.go`(执行 upload/download/delete/rename)、`rename_detect.go`(重命名/移动检测)、`index.go` / `helpers.go`(索引与共享工具)。

### 数据流

1. 用户仅从**文件同步**页创建/编辑配置:默认 `showAppModal` + `FileSyncProfileEditor(asDialog: true)`;仅 `preferModalSubWindows` 支持时走 debug 子窗口。
2. `_saveProfile` → `SyncProfileNotifier.saveProfile` → Go `saveSyncProfile` → `go/sync/store.go`。
3. `SyncProfileNotifier` 每 3 秒轮询 `listSyncProfiles` → Go `scheduler.go`/`runner.go` 运行时状态。
4. 周期或手动「立即同步」→ Go `runner.go` 跑 `diff.go` → `reconcile.go` → `executor.go`,经运行时适配器入队 `sync_*` 工作。
5. `FileSyncTasksPage` 从 `SyncProfileNotifier` 显示配置状态、从 `RemoteTaskStore.tasksForProfile()` 显示实时同步工作;`TransferQueue` 仅是生产者/执行兼容门面。

## LAN P2P D1/D2

同账号设备以 mDNS 自动发现,P2P 只加速通知与读取;对象存储的 `size + LastModified` 始终是版本权威,任何失败回退普通远端下载。设计文档见 [P2PSyncDesign.md](../P2PSyncDesign.md)。

**默认关闭的实验功能:** `RemoteStorageConfig.P2PEnabled` 在 `DefaultConfig()` 为 false,`UnmarshalJSON` 不为缺字段强制设 true。新账号/新配置不启动 mDNS,不再在无组播路由网卡刷 `no route to host`;显式保存 `p2pEnabled:true` 的配置保留(尊重已 opt-in 用户)。入口在「设置 → 局域网同步」(`SettingsP2PSection`,带「实验功能 · 默认关闭」标识)。启动门控:`dispatch_p2p.go` 读 `cfg.P2PEnabled && cfg.IsConfigured() && secret != "" && !cfg.Disabled`。回归锚点 `go/config/config_p2p_test.go`。

### 发现与传输

- `go/p2p/discovery.go` / `discovery_test.go` / `identity.go` / `events.go` / `manager.go` — `_cloudvolume._tcp` 在 `local.` mDNS 域只广播账号指纹与设备 ID;注册时服务名与完整域名分别传给 `hashicorp/mdns.NewMDNSService`,查询复用相同值。账户凭证 secret 在本机派生 HMAC key,事件同时用 HMAC 与 Ed25519 认证。`PeerManager` 维护实际 running 状态,配置账号变化时由桥接停止并重建。查询遇 `ENETUNREACH`/`EHOSTUNREACH` 按接口共享 2 分钟退避,避免无组播路由的 en0/en1 在多账号轮询中刷屏;其它 mDNS 错误正常记录,退避到期自动重试。
- **共享 mDNS socket(binding):** `go/p2p/discovery.go` 用单一 `sharedMDNS` 配 `multiServiceZone` 在一个 UDP 5353 socket 服务所有账号指纹。**绝不**每账号建一个 `mdns.Server`——端口冲突会静默丢弃广播。IPv6 mDNS 查询禁用(`DisableIPv6: true`):无可路由 IPv6 组播的 LAN 会让 hashicorp/mdns 刷 bind 错误;客户端查询与共享服务都传 `Logger: log.New(io.Discard, ...)`,库的 INFO/ERR 行不刷 bridge.log。
- **多接口查询(binding):** `queryPeers` 必须遍历 `multicastIPv4Interfaces()` 对每个接口分别查询。hashicorp/mdns 默认查询只用主接口;多网卡主机(如 en1 有 VMware 桥而 en0 是主接口)上默认查询会漏掉经次要接口可达的 peer。不要回退单默认接口查询。
- `go/p2p/transport.go` / `protocol.go` / `content_client.go` — QUIC 流承载有长度上限的 JSON 控制帧与原始 chunk bytes。查询、范围请求、查询响应与 chunk metadata 都有 HMAC;原始 bytes 传输时计算并校验绑定对象/版本/范围的 chunk HMAC;下载最多 4 路并发,chunk 大小限定 1–64 MiB。
- `bridge/dispatch_p2p.go` / `dispatch_config.go` / `dispatch.go` / `dispatch_object_transfer.go` — **多账号并行发现:** `ensureP2PManagers` 按档案名维护 `PeerManager` 表,为每个启用 P2P 的档案各注册一条 mDNS 服务(各自随机 QUIC 端口),profile 增删改(bootstrap/saveConfig/saveProfile/deleteProfile)后对账创建/替换/停止。两台设备共享任意一个账号即可互相发现,与活跃账号无关。**生命周期 key** `p2pSecretsKey` = storageType + endpoint + principal + secret 的 sha256——**绝不**用完整配置 JSON(时间戳等非凭证字段会在备份/恢复后变化并破坏发现)。每 manager 在自己的随机 QUIC 端口注册自己的 mDNS 服务实例(hashicorp/mdns 允许并行 server,按端口注册避免跨账号端口混淆)。**绝不**把 mutation 路由给「那个」manager:总是经 `managerForConfig(cfg)` 指纹匹配,否则账号 A 的事件会泄漏给只有账号 B 的 peer 并被认证检查静默丢弃。`BroadcastPayload.Config` 与 `broadcastPeerMutation(cfg, ...)` 携带发起方配置,桥接按指纹路由;`p2pStatus()` 聚合所有 manager 的 peer 并按 `accounts[]` 标注共享账号。远端确认的 bridge/mount mutation 广播父目录刷新;桥接上传与挂载写回的成功 `HeadObject` 登记本地源供 D2 读取。
- `go/mount/peer_hook.go` / `peer_content.go` / `bucket_remote.go` / `peer_refresh.go` — mount 经回调避免反向导入 `p2p`。读取顺序:本地完整 cache → P2P 临时 `.downloading` 文件 → 远端;P2P 完成后再次 `HeadObject` 检查版本,成功才按既有 stamp/rename 流程进缓存。`LocalPeerContentPath` 只提供匹配版本的完整缓存或远端已确认的上传源。

### 事件与内容安全

- **对端事件只触发受影响父目录的 `RefreshRemoteDirectory`**,绝不直接调 `NotifyExternalDelete`(后者会取消本机 pending writeback 并写 tombstone)。事件生产点只在 `writebackQueue.flushNow`、`deleteQueue.runDelete`、`bucketAccess.renamePath` 与桥接远端 mutation 成功点;P0 轮询(见 [mount_external_sync](mount_external_sync.md))继续是 P2P 不可用时的可靠性兜底。
- **D2 内容传输优先 provider ETag。** `go/s3.ObjectInfo` 从 Head/List 带回 ETag,缓存 stamp 持久化它,请求方在传输后复查。无 ETag 的 provider 用既有 `LastModified + size` 缓存版本回退——同秒同大小覆盖保留该已知限制,不强制全文件哈希。设置开关先持久化配置再发运行时切换(运行时禁用按 profile 记录在 `p2pDisabledProfiles`),manager 释放后禁用幂等。
- **自动发现选项(实验设计):** 可免配对,但组密钥只能在内存中由同一挂载范围的规范化 `storageType + endpoint + bucket + rootPrefix` 与实际凭证材料经 HKDF-SHA256 派生;mDNS TXT 仅广播截断 `HMAC(groupKey, "cloud-volume/p1/discovery/v1")` 标签与临时端口,绝不广播 endpoint、bucket、路径或凭证。标签匹配后建立 QUIC,首个双向流以随机 nonce、组密钥 HMAC 与 event MAC 认证,事件路径在该加密流内,接收端按父目录刷新。无需持久化新组密钥,但凭证轮换自然换组;匿名/无密钥账号不能启用;弱 WebDAV/FTP 密码会让广播标签成为离线猜测验证器——自动发现应默认关闭或明确告知该风险。不要依赖 HMAC `pathHash` 反查任意路径(不可逆);需传加密路径或只发已知目录刷新提示。

### Gotchas

- mDNS 的账号指纹不是认证材料;不能当 shared secret。
- 不要向 JSON/base64 放大 1–64 MiB chunk;不要为 P2P 增加强制全文件 hash 扫描。
- P2P 的可用性不改变写回、删除或 bootstrap 的成功语义。
