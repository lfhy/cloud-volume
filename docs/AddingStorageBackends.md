# 添加新的存储后端

本指南说明如何在云卷中接入一个新的远端存储类型（例如 FTP、SFTP、WebDAV 变体等）。
仓库已经实现了 S3、WebDAV、百度网盘、FTP、SFTP 后端，新增类型时请按下面的顺序改动。
每一层都给出了需要修改的文件和参考实现，尽量复用已有的抽象，避免大改公共代码。

## 改动总览

接入一个新存储类型通常需要改动五个层次，自下而上依次是：

1. Go 配置层：注册新的 `StorageType` 常量与归一化逻辑。
2. Go 存储后端：实现 `storage.Backend` 接口，并在 `ForConfig` 中路由。
3. Go 桥接层：确认桥接调用是否需要为新类型加分支（大多数情况下不需要）。
4. Dart 模型层：在 `StorageType` 枚举和 `RemoteStorageConfig` 中注册新类型。
5. Dart UI 层：在账号选择、表单、列表等处为新类型补充文案、图标、字段分支。

下面逐层展开。

## 1. Go 配置层

文件：`go/config/config.go`

- 在 `StorageType*` 常量块中新增常量，例如 `StorageTypeFTP = "ftp"`。
- 修改 `normalizeStorageType`，让新字符串能被识别；未知值仍回退到 `s3`。
- 如果新类型有自己的鉴权字段（例如 FTP 用户名/密码），建议新增专属字段而不是复用其他类型的字段，例如 FTP/SFTP 使用独立的 `FTPUsername` / `FTPPassword` / `FTPPort` / `FTPAnonymous` 字段，避免语义混淆。新增字段时需要同步更新 `RemoteStorageConfig` 结构体、`Normalized()`、`IsConfigured()`、`MergeStoredSecrets()`、`PublicSanitized()`、`WithDefaultWebDAVCredentials()` 等方法。
- 如果新类型的"映射桶名"默认值需要特殊处理，更新 `normalizeMappedBucketName`。
- `AccountLabel` 也要为新类型加上回退标签。

参考提交：百度网盘接入时在 `IsConfigured`、`AccountLabel`、`normalizeMappedBucketName`、`normalizeProviderType` 中都加了分支。

## 2. Go 存储后端

目录：`go/storage/`

新建一组文件，命名为 `<type>_backend.go`，必要时拆出 `<type>_backend_io.go`、`<type>_dirs.go`、`<type>_trash.go`、`<type>_quota.go` 等。
每个手写文件不要超过 500 行（见 AGENTS.md），按职责拆分。

需要实现的接口定义在 `go/storage/types.go` 的 `Backend`：

```go
type Backend interface {
    ListBuckets(context.Context) ([]BucketInfo, error)
    ListObjectsPage(context.Context, string, string, string, int32) (ObjectPage, error)
    ListObjectsRecursive(context.Context, string, string) ([]ObjectInfo, error)
    HeadObject(context.Context, string, string) (ObjectInfo, error)
    ReadObjectRange(context.Context, string, string, int64, int64) ([]byte, error)
    DirectoryAccess(context.Context, string, string) (DirectoryAccess, error)
    CreateDirectory(context.Context, string, string, string) error
    DeleteObject(context.Context, string, string, bool, string) error
    DeleteObjectHard(context.Context, string, string, bool, string) error
    ListTrashPage(context.Context, string, string, int32) (TrashPage, error)
    RestoreTrashItem(context.Context, string, string) error
    DeleteTrashItem(context.Context, string, string) error
    ClearTrash(context.Context, string) error
    RenameObject(context.Context, string, string, bool, string) error
    CopyObject(context.Context, string, string, string, bool, string) error
    MoveObject(context.Context, string, string, string, bool, string) error
    UploadFile(context.Context, string, string, string, string) error
    UploadReader(context.Context, string, string, io.Reader, int64, string, string) error
    DownloadFile(context.Context, string, string, string, string) error
    StreamObjectToHTTP(context.Context, string, string, bool, http.ResponseWriter) error
}
```

关键约定：

- 单根后端（WebDAV、百度网盘、FTP、SFTP）的 `ListBuckets` 只返回一个虚拟桶，桶名取自 `cfg.MappedBucketLabel()`。
- `ObjectInfo.Key` 对目录要以 `/` 结尾，与 S3 约定一致。
- 不支持回收站的操作可以直接返回空页或 `fmt.Errorf("...暂不支持...")`，参考百度网盘的 `ListTrashPage` / `RestoreTrashItem` 实现。
- 如果后端无法提供配额，不要实现 `BucketQuotaProvider`；`GetBucketQuota` 会回退为仅含桶名的结果。
- 如果后端较慢或有限流，实现 `MountPrefetchPolicy.SupportsMountPrefetch() bool` 返回 `false` 关闭目录预取。
- 如果需要自定义目录上传并发或重试，实现 `DirectoryUploadConcurrency() int` / `DirectoryUploadRetryDelay(error, int) (time.Duration, bool)`，参考 `baidu_pan_backend.go`。
- 只读桶检查：实现一个 `ensureBucketWritable(bucket)` 私有方法，参考 `webdav_bucket_policy.go` / 百度网盘。

在 `go/storage/types.go` 的 `ForConfig` 中为新类型加路由分支：

```go
if normalized.StorageType == storageconfig.StorageTypeFTP {
    backend = newFTPBackend(normalized)
}
```

`scopedBackend`（`RootPrefix` 支持）会自动包住返回的后端，无需自己处理前缀。

参考实现：`webdav_backend.go` 适合 HTTP 类后端；`baidu_pan_backend.go` 适合需要外部 SDK 和限流处理的 REST 类后端。

## 3. Go 桥接层

大多数新后端不需要改桥接，因为 `bridge/dispatch*.go` 通过 `storageops.ForConfig(input.Config)` 统一路由。

需要检查的例外：

- `bridge/dispatch_paging.go` 的 `listObjectPage` 对 WebDAV 跳过了挂载层缓存。如果新类型也不走挂载缓存（单根、无分页 token 等），需要把判断条件从 `!= StorageTypeWebDAV` 改成包含新类型，或改为白名单判断 S3。
- 如果新类型有独有的桥接命令（类似百度网盘的 OAuth 授权流程），新建 `bridge/dispatch_<type>.go`，并在 `bridge/dispatch.go` 的命令注册表里登记。

## 4. Dart 模型层

文件：`lib/models/remote_storage_config_enums.dart`

在 `StorageType` 枚举中新增成员：

```dart
enum StorageType {
  s3('s3', 'S3 对象存储'),
  webdav('webdav', 'WebDAV'),
  baiduPan('baidu_pan', '百度网盘'),
  ftp('ftp', 'FTP'); // 新增
  ...
}
```

同步更新 `StorageType.fromStorage` 的 switch，让新字符串能被解析。

如果有独立的 provider 类型，也要更新 `StorageProviderType`。

文件：`lib/models/remote_storage_config.dart`

- 如果新增了配置字段，更新构造函数、`empty()`、`fromJson()`、`toJson()`、`copyWith()`。
- `isConfigured` getter 要为新类型加上校验分支（参考 WebDAV 检查用户名/密码的逻辑）。
- `supportsShareLinks` 等能力 getter 按需调整。

## 5. Dart UI 层

新类型需要在以下文件中补充分支，否则 UI 会出现空白或回退到 S3 默认值。搜索 `StorageType.webdav` 或 `StorageType.baiduPan` 可以快速定位所有需要改动的位置。

账号选择 / 首次引导：

- `lib/widgets/config_storage_type_step.dart` — 首次启动的类型选择卡片，加一个 `_typeTile`。
- `lib/widgets/cloud_storage_account_dialog_steps.dart` — 账号管理对话框的类型选择步骤，更新 `_iconFor` 和 `_descriptionFor`。
- `lib/pages/config_setup_page.dart` — 首次引导默认 endpoint 与 `_selectStorageType` 的名称回退。
- `lib/pages/config_setup_save.dart` — 首次引导把表单字段映射为 `RemoteStorageConfig` 的保存分支;新类型必须明确鉴权字段、密钥保留与未配置提示,不得回落到 S3 语义。

表单字段：

- `lib/widgets/config_right_form.dart` 和 `lib/widgets/config_right_form_fields.dart` — 首次引导第二步的连接表单，为新类型决定显示哪些字段（endpoint / 用户名 / 密码 / 映射桶名等）。
- `lib/widgets/cloud_storage_account_dialog_steps.dart` 的 `stepConnectionFields` — 账号管理对话框的连接字段。
- `lib/utils/account_config_builder.dart` — 从表单草稿构建 `RemoteStorageConfig` 的逻辑，为新类型正确映射字段。

账号展示 / 列表 / 图标：

- `lib/widgets/cloud_storage_account_list.dart` — 账号图标。
- `lib/pages/cloud_storage_page.dart` — 账号保存校验提示文案。
- `lib/app/app_entry_io.dart` 的 `_accountEditorWindowSize` — 编辑窗口默认尺寸。
- `lib/app/sync_editor_window_app.dart` 和 `lib/pages/file_sync_tasks_page_actions.dart` — 同步任务里的账号来源标签。

文件管理页：

- `lib/pages/file_manager_page_access.dart` — 目录写权限检查。WebDAV 按目录探测权限；如果新类型是全局只读或全局可写，按百度网盘那样直接返回即可。
- `lib/pages/file_manager_page_object_loading.dart` — 列表加载行为（例如百度网盘需要限流提示）。

设置 / 桶设置：

- `lib/widgets/bucket_settings_dialog.dart` — 回收站文案。
- `lib/pages/settings_page_sections.dart` — 如果新类型有独有设置项。

## 6. 测试与验证

Go 侧：

- 为新后端编写 `go/storage/<type>_backend_test.go`，至少覆盖 `ListObjectsPage`、`HeadObject`、`UploadReader`、`ReadObjectRange` 等核心操作。参考 `webdav_backend_test.go` 的 httptest 模式。
- 运行 `go test ./...`。
- 如果需要本地桥接冒烟测试，用 `go build -o bin/...`，不要在仓库根目录执行 `go build .`。

Dart 侧：

- 运行 `flutter analyze`。
- 如果新类型有独立表单逻辑，考虑在 `test/` 下补充 widget 测试。

## 7. 文档

- `README.md` — 在功能导览中把新类型加入支持列表。
- `CHANGELOG.md` — 在 `## Unreleased` 下记录新特性。
- 如果新类型需要用户侧说明（例如 FTP 被动模式、端口配置），在 README 补充使用说明。
