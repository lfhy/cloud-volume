# Storage Backends — JWanFS FGW SDK 与 FTP/SFTP 后端

新增存储后端(任何新远端 provider)的五层改动指南见 [AddingStorageBackends.md](../AddingStorageBackends.md)。

## JWanFS FGW SDK(go/jwanfs)

从 `jwanfs/pkg/sdk/s3` 迁入 `go/jwanfs`,项目自持副本,不依赖 legacy `jwanfs/pkg/{jtool,types,consts,minio,s3ext}` 树。

### 关键文件

- `go/jwanfs/client.go` - 多网关上游池 `Client`、泛型故障转移 `doWithFallback`、`normalizeServers`/`firstConfiguredEndpoint`/`parseServer` 辅助。
- `go/jwanfs/lb.go` - `GatewayBalancer`:经 `fgwapi=gateway-list` 发现网关列表、并发 `/status` 健康探测、延迟排序回退池、每小时后台刷新。
- `go/jwanfs/sign.go` - 自含 AWS SigV4 签名(`NewSignedRequestV4`、`SignRequestV4`)+ `NewFGWAPI` URL 构建器。无 AWS SDK 依赖。
- `go/jwanfs/fgw.go` - FGW 业务 API:`FileInfo`/`FileInfoDetail`、`GetFileMD5`、`MoveObject`/`RenameObject`、`BucketQuota`、`FileSearch`、`CreateTempToken`/`UpdateTempToken`、`ShareDetail`、`AuthInfo`、`GetExpire`、`ShareFileURL`/`ResourceFileURL`/`StaticFileURL`。
- `go/jwanfs/fgw_request.go` - `DoFGWAPIRaw`/`DoFGWAPI[T]`/`doPublicFGWAPI[T]` 传输:签名 FGW 请求 + 故障转移 + `FGWResp[T]` 信封解码。
- `go/jwanfs/query.go` - `QueryValues` 包装 + `structToQueryValues` 反射编码器(取代 legacy `url.Values` + struct-tag)。
- `go/jwanfs/errors.go` - 哨兵错误(`ErrNoServer`、`ErrNoAvailableUpstreams`、`ErrAccessDenied`)、`shouldFallback` 分类、`httpStatusError`。
- `go/jwanfs/http_client.go` - `DefaultHTTPClient()` 共享连接池客户端,宽松 TLS(取代 `jtool.GetHttpClient`;自建网关常用自签证书——将来收紧 TLS 时同时更新它与网关探测)。
- `go/jwanfs/detect.go` - **JWanFS 网关检测**:`IsJWanFSGateway` 探测 `auth-info` FGW 路由;按 endpoint+凭证缓存(10 分钟 TTL)。`DetectionMode` = `auto`(默认)| `jwanfs` | `generic_s3`;字符串枚举持久化在配置 `jwanfsGatewayMode`,`auto` 探测一次并缓存、`jwanfs`/`generic_s3` 强制结果,endpoint 或凭证变化应调 `InvalidateDetectionCache(cfg)`。
- `go/jwanfs/types/` - 从 `jwanfs/pkg/types` 迁移的业务类型(全部 `size.B` → `int64`,`consts.*` → 本地枚举)。
- `go/s3/failover_pool.go` / `client.go` - 既有 AWS SDK v2 S3 操作经 `NewClient` 进入:用 `NewFailoverClient` 选择活跃 JWanFS 网关再返回 AWS client。所选 endpoint 按 endpoint/access-key/检测模式缓存一分钟,避免每对象请求做控制面发现,瞬态池随即停止。需要一次操作跨多上游重试的调用方必须自持池并调 `DoWithFallback`。

### 未迁移项(有意)

- `s3iface_bridge*.go`(~3000 行)— 适配 vendored aws-sdk-go-v1 的 `s3iface.S3API`;本项目用 aws-sdk-go-v2,无此接口。
- `s3.go` minio/aws 包装方法(`PutObject`/`GetObject`/`ListObjects`/`CreateMultipartUpload` 等)— 本项目在 `go/s3/` 用 aws-sdk-go-v2 直接实现。
- `AutoPutObject`/`AutoGetObject` 断点续传 — 本项目在 `go/s3/upload_resume*.go` 与 `object_transfer_*.go` 自有实现。

### 数据流

1. `NewClient(opt)` → `GatewayBalancer.Refresh()` 从首个配置 endpoint 发现网关列表。
2. 每网关 `GET /status` 探测;最快健康响应者成为主上游。
3. FGW API 调用(`DoFGWAPIRaw`)按序遍历上游池;可转移错误(5xx/429/网络)切下一上游并更新默认。
4. `IsJWanFSGateway(ctx, cfg, mode)` 构建瞬态 client 调 `AuthInfo`;成功即 JWanFS 网关,结果缓存,调用方可廉价门控 FGW 专属特性(`BucketQuota`、`FileInfo`、`FileSearch`)。
5. `go/s3.NewClient(cfg)` 复用一分钟缓存的 endpoint 或调 `NewFailoverClient(cfg)` 为 JWanFS 账号选出当前 AWS SDK v2 endpoint,然后停掉瞬态 balancer。

### Gotchas

- `go/s3` 仍是 AWS SDK v2 数据面,`go/jwanfs` 提供 FGW 业务 API 与网关发现;`go/s3/failover_pool.go` 有意 import `go/jwanfs` 为 JWanFS 账号选活 endpoint。
- FGW `bucket-quota` 路由的 `Total`/`Free`/`Used` 是 JSON 数字;legacy `size.B` 就是 `int64`,迁移后的 `GetBucketQuotaRes` 直接用 `int64`。
- JWanFS 检测/构造期超时与拨号超时约束见 [account_management](account_management.md) 多账号桶加载韧性一节。

## FTP / SFTP 远端存储后端

FTP 与 SFTP 把远端服务器呈现为单一虚拟桶,保持文件管理器、传输队列与桥接共享的后端接口。

### 关键文件

- `go/config/config.go` - 定义 `ftp`/`sftp` 存储类型与共享连接字段(`FTPUsername`、`FTPPassword`、`FTPPort`、`FTPAnonymous`)。零端口选择协议默认:FTP 21、SFTP 22。
- `go/storage/types.go` - `ForConfig` 选择后端并在配置 `RootPrefix` 时应用 `scopedBackend`,普通对象操作保持视图相对。
- `go/storage/ftp_backend*.go` - 经典 FTP listing、文件 I/O、目录 mutation、递归 listing/拷贝、硬删除。FTP 返回未知配额(协议无标准容量 API)。
- `go/storage/sftp_backend*.go` - 经 `pkg/sftp` 实现 SFTP listing、文件 I/O、mutation;`sftp_backend_quota.go` 在服务器提供时用可选 `statvfs@openssh.com` 扩展。`HeadObject` 只把真实缺失路径映射 `os.ErrNotExist`,保留权限/连接失败使 metadata 验证可带可操作错误重试。
- `go/storage/ftp_mock_test.go` / `sftp_mock_test.go` 及后端测试 - 对进程内 mock 服务器跑协议级集成测试。
- `lib/models/remote_storage_config.dart`、`lib/models/cloud_storage_account_draft.dart`、`lib/utils/account_config_builder.dart`、`lib/widgets/cloud_storage_account_dialog*.dart`、`lib/pages/config_setup_page.dart`、`lib/widgets/config_right_form*.dart` - 持久化设置并呈现协议专属账号表单。

### Gotchas

- `FTPPort` 与 `FTP*` 凭证字段目前也用于 SFTP;不要从字段名推断默认端口。
- 可选后端能力被 `scopedBackend` 隐藏,除非包装器转发。增改 `BucketQuotaProvider` 行为时,用非空 `RootPrefix` 验证 `storage.GetBucketQuota`,不要只调具体后端。
- SFTP 目录删除是递归的。保持 `TestSFTPCreateAndDeleteDirectory` 内有嵌套文件,未来重构不能回归到只 `RemoveDirectory`。
- FTP 与 SFTP 的 `UploadFile`/`UploadReader` 经共享 `runTrackedUpload` 消费非空传输任务 ID。保持两个协议级回归测试断言 `14/14` 完成快照,挂载写回不能回归到滞留 `sync_wait` 行。
- **SSH host-key 验证按安全边界对待:** 密码认证的 SFTP 后端在生产中不得静默接受变更的 host key。
- SFTP 的 mtime 时区归一化(与 FTP/WebDAV 共享)见 [mount_metadata_core](mount_metadata_core.md) 持久元数据核心一节;SFTP 禁用挂载预取与远端轮询的策略见 [macos_webdav_mount](macos_webdav_mount.md)。
