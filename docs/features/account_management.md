# Account Management — 账号管理、首启配置与多账号桶加载

覆盖:账号管理页(增删改、禁用、排序)、首次启动配置向导、桶可见性/别名/配额、多账号桶加载的并发/超时/去重/负缓存。

## 账号管理页

列出已配置存储账号,支持新增、编辑、移除。**默认路径**:新增/编辑以应用内模态打开(`showAppModal` + `CloudStorageAccountDialog(asDialog: true)`);仅 debug(`preferModalSubWindows`)可 spawn 分离 OS 子窗口(子窗口壳见 [app_modal](app_modal.md))。

**三步向导(新账号):**
- **Step 0「选择协议」:** S3 / WebDAV / 百度网盘 大可选卡片;选中卡片只更新 `_storageType`,不导航。
- **Step 1「连接信息」:** 名称 + 协议连接字段 + `AccountProxySection`(每账号代理,见 [settings](settings.md) 的账号独立代理节)。
- **Step 2「桶列表显示设置」:** 拉取 live 桶做多选 allowlist;每个选中桶可设显示别名与远端 root prefix。空选择 = 动态全部。
- **编辑模式**不用向导,渲染单屏连接表单(`_buildEditContent`),仅 Cancel/Save。
- 步骤导航只有 `_next` / `_back`(账号编辑器无步骤标签/`_goToStep`)。

**窗口尺寸策略:** 账号编辑器不再调 `resizeKeepingWindowCenter`。初始 OS 窗口尺寸由 `app_entry_io._accountEditorWindowSize` 在 spawn 时固定:新账号种子 `528×340`(step 0),最终尺寸首次布局后按内容测量;编辑模式按协议:Baidu `520×520`、WebDAV `520×600`、S3/默认 `520×700`。最小尺寸来自 `configureDesktopModalSubWindow` 默认 `480×400`。打开服务(`AccountEditorWindowService`)只创建窗口并传创建者 frame,不设尺寸。Shell `AccountEditorWindowApp` 仅在内容超出屏幕钳制时用 `DesktopModalSubWindowApp(scrollable: true)` 作溢出保护;常规步骤测量内容并经 `fitModalSubWindowToContentSize` 调整 OS 窗口。对话框子窗口内容返回 `SizedBox(width: 480)` + `Column(mainAxisSize: min)` 收缩包裹高度。

**关键文件:**
- `lib/services/account_editor_presenter.dart` — 账号新增/编辑的唯一呈现入口:仅在 `preferModalSubWindows` 允许时开 debug 子窗口,否则 `showAppModal` + `CloudStorageAccountDialog(asDialog: true)`。
- `lib/pages/cloud_storage_page.dart` — 账号管理把增删改呈现委托给 presenter;`_toggleDisabled(profile, disabled)` 镜像 `_delete`/`_saveEditedAccount`:`loadProfile` → `copyWith(disabled:)` → `saveProfile` → `onRefresh` + busy guard + toast。同时拥有状态列探测 `_refreshStatus()`:禁用账号直接标 `AccountStatus.disabled` 不探测,每个启用账号并发 `_probeAccount(name)`(`loadProfile` + `listBuckets`,12 秒 Dart 超时,复用快速失败路径使一个不可达账号不拖慢页面并为文件管理播种共享负缓存)。
- `lib/pages/file_manager_page_sources.dart` / `file_manager_page_bucket_loading.dart` — source 失败携带精确 `profileName`;只有最新加载 generation 可发布错误,防止重叠启动重载把失败账号目标替换成活跃/第一账号。
- `lib/pages/file_manager_page.dart` — 桶列表错误视图次级动作是**「账号管理」**,接 `onOpenAccountManagement`,`main_layout_page.dart` 解析为 `onSelectedItemChanged(SidebarItem.storage)`:跳到账号管理页(可编辑/禁用/重启)而不是原地开单 profile 编辑器。
- `lib/widgets/cloud_storage_account_dialog.dart` — 向导/编辑 UI;双模式 `asDialog`(默认 true)。
- `lib/widgets/cloud_storage_account_dialog_steps.dart` — `stepProtocolPicker` / `stepConnectionFields`、高级设置 chrome 与窄屏单/双列编排;`StorageProtocolCard` 是 hover 正典(见 [ui_rules](ui_rules.md))。
- `lib/widgets/cloud_storage_account_dialog_fields.dart` / `cloud_storage_account_dialog_oauth.dart` — S3/WebDAV/FTP/SFTP/Baidu 字段组与 Baidu OAuth 动作;从主 widget/steps 拆出以维持 500 行上限。
- `lib/widgets/cloud_storage_account_dialog_bucket_loading.dart` / `cloud_storage_account_dialog_bucket_visibility.dart` — 拉取 live 桶、编辑第三步 allowlist/别名/prefix。
- `lib/widgets/cloud_storage_account_dialog_credentials.dart` — S3 Access Key/Secret Key 被修改时暴露显式验证按钮,调桥接 `validate_account_credentials`;`bridge/dispatch_config.go` 对 S3 用 `s3.CheckAccess`、其它后端用 `ListBuckets` 验证,不持久化任何东西。
- `lib/models/cloud_storage_account_draft.dart` / `lib/utils/account_config_builder.dart` / `lib/utils/account_profile_name.dart` — 草稿、配置构建、profile key。`buildAccountConfig` 在编辑字段为空时保留已存 S3/WebDAV/FTP 密码;编辑器绝不把 secret 水合进 Flutter。
- Debug 子窗口架构(保留):`lib/models/account_editor_window_args.dart`、`lib/app/account_editor_window_app.dart`、`lib/services/account_editor_window_service.dart`(+`_io`/`_web`)、`lib/app/app_entry_io.dart` / `desktop_modal_window_config.dart` / `desktop_sub_window_modal.dart` / `desktop_window_method_host.dart`(spawn、尺寸、chrome、`account_editor_saved` 仅 debug 路径)。

**数据流:**
1. 用户在 `CloudStoragePage` 点「新增账号」或行内「编辑」。
2. 默认:presenter 开 `showAppModal` + `CloudStorageAccountDialog(asDialog: true)`;保存经页面 `_saveNewAccount` / `_saveEditedAccount` → `api.saveProfile` → `onRefresh`。
3. Debug only:`AccountEditorWindowService.openEditor` 支持时 spawn OS 子窗口;保存经 `account_editor_saved` 通知创建者并关闭子窗。
4. 文件管理恢复定位失败的桶列表 source 或点击失败的桶,用同一 presenter 编辑模式保存并刷新 bootstrap 会话。
5. Baidu OAuth 成功为新账号保留已授权草稿并前进到桶可见性;编辑模式仍立即 `_submit`,恢复行为不变。

## 账号禁用

账号可从账号管理页禁用。禁用账号被保留(可重新启用),但在所有会连接后端的地方被跳过:不列桶、不显示为加载失败、不参与 P2P、配额预取不联系它。

- `go/config/config.go` — `RemoteStorageConfig.Disabled bool`(`json:"disabled" toml:"disabled"`)。零值 `false` = **启用**,无需 `UnmarshalJSON` shim(对比 `P2PEnabled`,后者默认改 false 才需要 shim)。`Normalized()` 原样透传。
- `go/config/profile.go` — `ProfileInfo.Disabled bool`,在 `go/config/config_db.go` `listProfilesFromDB` 从 `normalized.Disabled` 填充。
- `bridge/dispatch_p2p.go:81` — P2P manager 门控读 `cfg.P2PEnabled && cfg.IsConfigured() && secret != "" && !cfg.Disabled`;禁用账号绝不启动 P2P manager。
- `lib/models/remote_storage_config.dart` / `remote_storage_config_copy.dart` — `disabled` 字段(默认 false,fromJson,toJson 省略 false,copyWith)。
- `lib/models/bootstrap_state.dart` — `ProfileInfo.disabled`(`json['disabled'] == true`)。
- `lib/services/bucket_source_service.dart` — `loadEntriesWithFailures` 与 `loadSources` 在任何 `loadProfile`/`listBuckets` 调用**之前**过滤 `profiles.where((p) => !p.disabled)`。这是文件管理、全局回收站、同步选择器的单一门控。
- `lib/widgets/cloud_storage_account_list.dart` — `_AccountActions`(列表)与 `_AccountCard`(网格)显示 `ShadSwitch`(value = `!profile.disabled`),切换调 `onToggleDisabled`。禁用账号标题加「(已禁用)」后缀。本文件同时持有 `enum AccountStatus { checking, ok, error, disabled }` 与 `_AccountStatusChip`(点 + 标签 + tooltip)。
- 回归锚点:`go/config/config_disabled_test.go`、`test/bucket_source_service_test.dart`(`loadEntriesWithFailures skips a disabled account entirely`)。

**Gotchas(binding):**
- **`Disabled=false` 即启用。** 零值就是期望默认;缺字段、旧配置、`DefaultConfig()` 都是启用。禁用永远是显式用户动作。不要加强制默认的 `UnmarshalJSON` shim。
- **在 service 过滤,不在页面过滤。** `BucketSourceService` 是共享入口;在那里过滤保证所有消费者一致。不要在 `FileManagerPage` 过滤(profiles 列表还用于挂载状态与重新启用流程)。
- **账号管理页永不过滤。** 禁用账号必须带着开关可见,否则无法重新启用。

## 首次启动配置(First-run Config Setup)

首启/不完整配置的引导,位于主 shell 之前。内容在桌面标题栏 chrome 下延伸(无页面级顶部 padding)。

**分步布局:**
- **Step 0「选择协议」:** 分栏——左品牌(`ConfigLeftPanel`),右类型选择(`ConfigStorageTypeStep`)。
- **Step 1「连接信息」:** 全宽表单——左品牌**隐藏**使表单用满窗口宽;`ConfigRightFormPanel(fullWidth: true)`。宽窗口时 S3/WebDAV 字段两栏布局避免单栏滚动;Baidu OAuth 保持单栏(auth 块已宽)。
- **步骤切换:** Next/Back 用 `TweenAnimationBuilder` + `ClipRect/Align(widthFactor)` 滑动折叠左品牌,右侧用非堆叠 `AnimatedSwitcher`(~240ms)淡入。无中间 spinner 页。

**关键文件:** `lib/pages/config_setup_page.dart`(向导宿主)、`lib/pages/config_setup_save.dart`(首启账号草稿校验与持久化 part)、`lib/widgets/config_storage_type_step.dart`(step 0 类型卡片)、`lib/widgets/config_right_form.dart`(step 1 表单壳 + Back/Save/高级对话框;`fullWidth` 放宽表单(max ~720)并在视口 ≥700 启用两栏)、`lib/widgets/config_right_form_fields.dart`(字段构建器 part 文件)、`lib/widgets/config_left_panel.dart`(品牌/标语/强调色选择器,仅 step 0)、`lib/pages/app_bootstrap_page.dart`(路由到此当 `!state.configured` 或「重新配置认证信息」)、`lib/pages/login_page.dart`(Web 登录仍用左品牌 + 表单分栏,独立于首启步骤布局)。

**默认网关(IHEP):** S3 `https://fgws3-ocloud.ihep.ac.cn`;WebDAV `https://webdav-ocloud.ihep.ac.cn`;百度网盘 `https://pan.baidu.com`(OAuth,不可编辑)。字段为空或仍是已知 preset 时应用;用户输入的自定义 URL 在切换协议卡片时**不**被覆盖。

**Gotchas:**
- **不要**给 Scaffold body 加顶部 padding 避让 `DesktopWindowControls`——那会在两栏上方制造全宽白带。Baidu step-1 Back 用原 padding 已可用;除非复现真实 hit-test bug,避免布局 hack。
- Step 1 刻意去掉左品牌使长表单少滚动;step 0 保留品牌承载首启营销/强调色。
- 账号管理模态向导(`CloudStorageAccountDialog`)是独立路径,不预填 IHEP 默认;只有首启 setup 填。
- 保存仍走 `api.saveConfig`(legacy 首启 profile `"default"`)。

## 多账号桶加载韧性(并发/超时/去重/负缓存)

桌面加载桶列表必须并发、按账号隔离、带超时、去重、负缓存——一个不可达上游不能阻塞其它账号、不能重复拨号、不能整页卡死。

### 关键文件

- `lib/services/bucket_source_service.dart` — `loadEntriesWithFailures` 经 `Future.wait` **并发**加载 profiles 与列桶,每账号 try/catch 隔离(`_loadSource`/`_listBucketsForSource` + `_SourceLoadOutcome`/`_BucketListingOutcome`)。每个 `loadProfile`/`listBuckets` 包 `.timeout(_perAccountTimeout = 40s)`。失败/卡死账号进 `failures`(驱动「重新配置」错误条)而不阻塞健康账号。profile 顺序为确定性回退排序保留。带可选 `force` 标志。
- `bridge/dispatch.go` — `listBuckets` 包 `context.WithTimeout(context.Background(), bridgeListBucketsTimeout = 30s)` 并经 `storageops.ListBucketsDedup`(singleflight + 负缓存)路由。`listBucketsArgs` 带可选 `force`。
- `go/storage/list_buckets_cache.go` — `ListBucketsDedup(ctx, cfg, listFn, force)`:singleflight 把同一连接身份的 N 个并发调用方折叠为一次上游拨号;20 秒每账号负缓存(`listBucketsNegativeCacheTTL`)立即返回上次失败,已知坏账号不在每次页面加载时重拨;`force: true` 绕过负缓存(用户显式刷新),成功清除过期条目。以 `bucketListIdentityKey`(连接身份,账号隔离)为 key。
- `go/s3/buckets.go` — `bucketListTimeout = 8s`,单个 ListBuckets 在负缓存记录前快速失败。
- `go/s3/failover_pool.go` — S3 客户端构造的 JWanFS 网关检测(`IsJWanFSGateway`)跑在 `jwanfsDetectionTimeout = 10s` 下。
- `go/jwanfs/detect.go` / `client.go` — `NewClient` 的初始 `balancer.Refresh` 跑在 `gatewayRefreshTimeout = 10s` 下;失败照旧回退直连。
- `lib/services/remote_storage_gateway.dart` / `remote_storage_api_desktop_storage.dart` / `remote_storage_api_web_transfers.dart` — `listBuckets(config, {force = false})`;桌面把 `force` 透传到桥接。
- `lib/pages/file_manager_page.dart` / `file_manager_page_bucket_loading.dart` / `file_manager_page_sources.dart` — `_loadBuckets({force})`;用户显式「返回桶列表」导航与错误视图「重试」传 `force: true`。自动重载(启动、挂载后、重排后)保持非强制以复用负缓存。

### Gotchas(binding)

- **TCP 拨号超时(「等超时」投诉的根因)。** 应用内每个 HTTP transport(`go/config/proxy.go` `ProxyTransport` 经进程级 `boundedDialer`、`go/s3/client.go` `newSingleEndpointClient`(现总是用 `ProxyHTTPClient`)、`go/jwanfs/http_client.go` `DefaultHTTPClient`)应用 3 秒 `DialContext` 超时。没有它,**丢包**端点(关机网关、防火墙 DROP、不可路由 IP——不是 RST「connection refused」)让 macOS OS 级 SYN 重试约 75 秒,只有每请求上下文(8 秒 `bucketListTimeout`)能打断。实测:默认 dialer = 75.011s,3 秒 dialer = 3.000s。**不要**移除任何这些 transport 的 `DialContext`,不要让 S3 客户端回退 AWS SDK 默认 HTTP client(无拨号超时)。「connection refused」(RST)仍立即返回;拨号超时只约束 DROP 场景。
- singleflight + 负缓存住在 **Go**(`ListBucketsDedup`),以连接身份为 key。并发的 3 个 `list_buckets s3 test` 调用(文件管理 + 全局回收站 + 配额预取)共享一次上游拨号而不是各自等 8 秒以上。
- 失败缓存 `listBucketsNegativeCacheTTL = 20s`。窗口内非强制重载立即返回缓存错误(不拨号)。用户显式刷新(`force: true`)**必须**绕过,让修好的账号可重试——`force` 只接两个用户主动路径,不接自动重载,否则负缓存无意义。
- jwanfs `IsJWanFSGateway` 与 `NewClient` 的 `balancer.Refresh` 在 **S3 客户端构造期间**跑,先于任何每请求上下文。它们曾用 `context.Background()`,不可达端点卡 OS 级 TCP 超时(约 1–2 分钟)。构造期探测必须显式设限;bridge/req 超时只约束 `ListBuckets` 内部。
- `bridge list_buckets` 用 `context.Background()`(无入站 HTTP 请求可继承期限),所以**必须**自建超时——否则单个不可达 S3 账号无限挂起桥接调用。
- Flutter `_perAccountTimeout`(40s)刻意长于 Go `bucketListTimeout`(8s)+ 构造(10s),后端描述性错误优先于泛化 Dart `TimeoutException`。
- FTP/SFTP/WebDAV/Baidu `ListBuckets` 都立即返回合成桶不联系服务器,实践中不会挂起或被负缓存;只有 S3(及其 JWanFS 网关探测)在列桶期间真正拨出。
- 回归锚点:`go/storage/list_buckets_cache_test.go`(singleflight 折叠、负缓存快速失败、force 绕过 + 清除、账号隔离)、`go/jwanfs/detect_test.go`(构造期超时)、`test/bucket_source_service_test.dart`(Flutter 隔离 + 卡死超时)。保持绿色。

## 桶可见性(bucketViews)

- `RemoteStorageConfig.bucketViews` / Go `BucketViews` 是按 provider 桶名 key 的 map。空 map = 动态全部(含之后创建的桶);非空 map = 显式 allowlist。`BucketViewSettings` 持有 `displayName` 与 `rootPrefix`;归一化在 `lib/models/bucket_view_settings.dart` 与 `go/config/config_bucket_views.go`。
- 向导流程:协议 → 连接/OAuth → 桶可见性;`cloud_storage_account_dialog_bucket_loading.dart` 验证草稿并拉 live 桶,`cloud_storage_account_dialog_bucket_visibility.dart` 持有选择、别名输入、共享 `remote_directory_picker_dialog.dart` 入口。Baidu OAuth 保留已授权草稿前进而不是立即保存。S3 返回真实桶;WebDAV/Baidu 返回单合成桶——所有 provider 用同一选择 UI 与持久化模型。清空最后一个勾选回到动态全部。
- `lib/pages/file_manager_page_sources.dart` 与 `file_sync_tasks_page_actions.dart` 只在 map 非空时过滤 provider 结果。`FileManagerBucketEntry` 保留 provider 桶名作为稳定操作/ID 值,别名走 `label`,构建账号 prefix 与所选桶 prefix 拼接的有效配置。桶列表、面包屑、远端选择器、挂载消息用别名而不改后端标识。
- `go/storage/scoped_backend.go` 是共享对象路径边界。`storage.ForConfig` 在 `RootPrefix` 非空时包装 S3/WebDAV/Baidu;list/head 结果翻译回视图相对 key,list、mutation、传输、回收站、流式、目录访问、分片上传翻译出向 key。可见性(哪些桶出现在 UI)刻意不在这里强制——它属于更高层 loader,因为 `ListBuckets` 仍必须为同步、挂载、配额、目录选择器返回真实 provider 集。`ListTrashPage` 过滤前分配新 slice(provider 回收站页可能共享底层数组),只呈现 provider `OriginalKey` 在视图 root 下的条目并重写为视图相对路径;`RestoreTrashItem`/`DeleteTrashItem` 直接委托原始 `trashID`,因为 provider 回收站元数据已记录全 scoped `OriginalKey`。`storage.IsScoped` 暴露 backend 是否被包装,调用方可断言 prefix 翻译所有权。
- 挂载层所有权:`go/mount/bucket_access.go` 调 `storage.ForConfig` 前清 `RootPrefix`,自己经 `remotePrefix`/`remoteKey`/`virtualKey` 做全部 prefix 翻译。任何其它路径都会双重加前缀。`bucket_access_root_prefix_test.go` 断言构造的 backend 未 scoped。
- 测试:`go/config/config_bucket_views_test.go`、`go/storage/scoped_backend_test.go`、`go/mount/bucket_access_root_prefix_test.go`、`test/bucket_quota_test.dart` 覆盖归一化、动态全部 vs allowlist JSON、虚拟路径翻译、不改 provider 状态的 scoped 回收站过滤、挂载 unscoped-backend 契约。

## 账号/桶存储模型(Go 侧)

账号是多 profile 配置,不是独立「account」表。账号与桶都有持久化自定义排序(见下)。

- `go/config/config.go` — `RemoteStorageConfig`(完整账号连接 JSON)、`BucketSettings`、`BootstrapState`。
- `go/config/profile.go` — 公共 profile API:`SaveProfile`、`LoadProfile`、`ListProfiles`、`DeleteProfile`、`SetActiveProfile`、`ResetAllProfiles`;摘要 DTO `ProfileInfo`。
- `go/config/config_db.go` — bbolt 持久化在 `~/.cloud-volume/config.db`:bucket `profiles`(key = profile 名,值 = JSON `RemoteStorageConfig`);bucket `meta`(key `active_profile`,全局代理经 `global_proxy.go`)。`listProfilesFromDB` 排序:活跃优先,然后 `default`,然后名字母序。
- `go/config/store.go` — `SaveProfileWithValidation`(首启完整性检查)后 `saveProfileToDB`。
- `go/s3/buckets.go` — live `ListBuckets` → `[]BucketInfo{Name}`;S3 provider 顺序,本地不重排。
- `go/storage/webdav_backend.go` / `baidu_pan_backend.go` — 单合成桶(`MappedBucketLabel` / Baidu 标签)。
- 桶列表 UI(加载与聚合):`lib/pages/file_manager_page.dart` 持有 `_buckets`;`lib/pages/file_manager_page_sources.dart` 多账号聚合(loadProfile → listBuckets → `FileManagerBucketEntry`(id = `profileName::bucket.name`)→ 应用持久顺序);`lib/pages/file_manager_page_bucket_view.dart` 从 `_filteredBuckets` 构建 `FileManagerBucketBrowser`;`lib/pages/file_manager_page_state.dart` 的 `_filteredBuckets` 只按搜索过滤、保留加载顺序。行模型 `lib/models/file_manager_bucket_entry.dart` / `lib/models/s3_objects.dart` 的 `BucketInfo`(带可选 `quotaBytes`/`usedBytes`/`quotaKnown`,无顺序字段)。`FileManagerBucketBrowser` 响应式列表列优先保证动作格:720px 以下折叠独立 source 列(source 保留在名称副标题),420px 以下折叠配额列,`showActionColumn` 启用时动作列始终保留。同一聚合模式也被 `file_sync_tasks_page_actions.dart` 的远端选择器复用。账号 glyph 恒为 `cloud`(协议只在类型标签显式标出);侧栏用独立的 `cloudCog` 表示账号管理功能而非任何协议。

**JSON schema(Go → Flutter):**
- `RemoteStorageConfig`:`endpoint`、`storageType`、`providerType`、`displayName`、`mappedBucketName`、`region`、`bucket`、`accessKeyId`、`secretAccessKey`、`hasSecretAccessKey`、`webdavUsername`、`webdavPassword`、`hasWebdavPassword`、`rootPrefix`、`defaultDownloadDirectory`、`cacheDirectory`、`resolvedCacheDirectory`、`hideDotFiles`、`fileOpenMode`、`trashDirectoryName`、`trashRetentionDays`、`bucketSettings`(map)、`bucketViews`(map)、挂载/缓存/代理字段。**无内联 order/sort 字段。**
- `BucketSettings`:`readOnly`、`trashEnabled?`、`trashDirectory`、`customQuotaBytes`、`winFspVolumeLabel`;map key 是桶名,**无顺序**。
- `BucketViewSettings`:`displayName`、`rootPrefix`;key 是不可变 provider 桶名;父 map 空即动态全部。
- `ProfileInfo`:`name`、`displayName`、`storageType`、`providerType`、`endpoint`、`accessKeyId`、`active`、`disabled`。
- `BootstrapState`:`configPath`、`configured`、`config`、`profiles[]`。
- live 桶行 `BucketInfo`:`name` + 可选 `quotaBytes`/`usedBytes`/`quotaKnown`(区分真实零用量与不支持查询)。

**桥接 API(账号/profile):** `load_bootstrap_state` / `migrate_default` → `BootstrapState`;`save_config`(legacy 首启,存 profile `default` 并设活跃);`list_profiles`;`load_profile {name}`;`save_profile {name, config}`;`delete_profile {name}`;`set_active_profile {name}`;`reset_user_config {confirm}`;`update_proxy_settings`(仅全局代理);`list_buckets {config}`(live,不存储)。

## 自定义排序(账号与桶)

- Meta key(`config.db`):`profile_order`(JSON `[]string` profile 名)、`bucket_order`(JSON `[]string` 条目 id `profileName::bucketName`)。
- Go:`go/config/list_order.go`(`ReorderProfiles`、`ReorderBuckets`、`ListBucketOrder`,apply/append/remove 辅助)。`listProfilesFromDB` 有 `profile_order` 时使用之,否则 legacy 排序。
- 桥接/webapi:`reorder_profiles {names}`、`reorder_buckets {ids}`、`list_bucket_order`;Flutter gateway:`reorderProfiles`/`reorderBuckets`/`listBucketOrder`。
- UI:账号列表 `CloudStorageAccountList` 列表模式 `ReorderableListView` + `CloudStoragePage._reorderAccounts`(乐观本地顺序);桶列表 `FileManagerBucketBrowser` 列表模式重排 + `file_manager_page_bucket_view.dart` 的 `_reorderBuckets`;加载路径应用 `listBucketOrder`(回退:profile 顺序再桶名)。网格/搜索/回收站首页不启用拖拽重排(框选拖拽 `file_manager_drag_selection.dart` 与重排无关)。**注意 Flutter 3.41.6 工具链约束(见 [remote_tasks](remote_tasks.md) Transfer Queue gotchas):保持经典 `onReorder` 回调。**
- Bootstrap 软刷新:`lib/pages/app_bootstrap_page.dart` 保持 `_session` 挂载并原地重载 bootstrap 状态;重排不触发全屏 loading shell。
- 保存 profile 把新名字追加进 `profile_order`;删除 profile 剥离该 profile 及其 `profile::` 桶 id;reset 清两条 order。
- 重排模式正典:`ReorderableListView.builder` + `ReorderableDragStartListener`(自定义握把;无默认尾把手),在 `lib/widgets/cloud_storage_account_list.dart` 与 `lib/widgets/file_manager_bucket_browser.dart`。

## 桶自定义配额与远端配额发现

- `BucketSettings.CustomQuotaBytes`(`customQuotaBytes` JSON / `custom_quota_bytes` TOML;`go/config/config_bucket_settings.go` 归一化负值为零,零即未设)。Dart `lib/models/bucket_settings.dart` 镜像(camelCase+snake_case 兼容,零省略,legacy 负值钳零);`lib/models/remote_storage_config_enums.dart` 持有持久化枚举使主 config 模型保持行数内。`lib/widgets/bucket_settings_dialog.dart` 按 GB 编辑(小数,转字节,零/空即未设)。值仅信息展示,不强制上传上限。
- 桶列表 UI:`lib/widgets/file_manager_bucket_browser.dart` 用 `FileListTile` 尺寸列作响应式「已用 / 配额」列;`lib/widgets/file_manager_bucket_quota.dart` 持有总量解析与列表格式。卡片刻意省略容量文字/进度(Finder 式 tile 固定高度);列表模式优先 `CustomQuotaBytes` 作总量,回退 `BucketInfo.quotaBytes`:`quotaKnown` 用真实用量填充轨道,只有总量的后端(通用 S3)显示中性空轨道 `用量未知 · total`,无任何总量显示 `未设置额度` 同空轨道。`FileListTile.sizeWidget` 允许富容量格而不改其它行。`lib/utils/transfer_format.dart` 格式化 TB。
- 挂载容量:`go/mount/mount_capacity.go` 依次取桶 `CustomQuotaBytes` → provider 配额 → 后端回退。WinFsp 全局 `windowsWinFspCapacityGB` 只是最终回退;Linux FUSE 无回退,未设配额保持零 Statfs。`backend_windows_winfsp_cgo.go` 会话启动时快照已解析容量与 provider 已用字节;`winfsp_fs_windows.go` 报告 total/free/available 块。均用 4096 字节块;WinFsp 有 provider 已用时减去,否则 free 镜像 total。改配额需重挂。Cloud Files 与 WebDAV 挂载无应用 Statfs 回调,容量由宿主文件系统/客户端控制;macOS 回环 WebDAV 是例外:RFC 4331 dead properties(`go/mount/webdav_quota.go`)让 `webdavfs` 把缓存配额投进 `df`。
- `BucketSettings.WinFspVolumeLabel`(可选,≤32 字符)经 `BucketSettingsFor` 流入下次 WinFsp 挂载的卷标。
- **远端配额发现:** 通用 S3 `ListBuckets` 无配额/用量;可靠 S3 配额需要 provider 管理面 API,递归求和昂贵且不是配额。`go/s3.BucketInfo` 是共享桥接负载,带可选 `quotaBytes`/`usedBytes`。`go/storage/webdav_quota.go` 对映射根做 depth-0 RFC 4331 PROPFIND,解析 `quota-used-bytes`/`quota-available-bytes`,经 `BucketQuotaProvider` 报告;失败走中央 `logging.Errorf`。Baidu:`go/storage/baidu_pan_quota.go` 调 xpan `Client.Quota()`(`checkfree=1&checkexpire=1`),映射 total/used;配额错误不阻塞首屏桶列表;`go/storage/baidu_pan_sdk.go` 把百度配额专属 `用户未登录` 当过期认证态,首个配额请求刷新 OAuth 并重试;刷新凭证回写匹配的实际存储 profile(可能非活跃账号);刷新/持久化/重试失败分别记日志。
- 二段请求:`bridge/dispatch_bucket_quota.go` 暴露 `get_bucket_quota`;`lib/services/remote_storage_gateway.dart` 要求 `getBucketQuota` 使运行时能力检查失败也不能跳过;桌面在 `remote_storage_api_desktop_storage.dart` 实现,Web 经 `remote_storage_api_web_transfers.dart` / `go/webapi/invoke.go` 转发。`file_manager_page.dart` 持有页面会话配额缓存;`file_manager_page_bucket_loading.dart` 重新应用缓存并在单次列表 `setState` 前等待 `lib/pages/file_manager_page_quota.dart` 的 provider 请求(避免旧 post-frame 行重建破坏 hover)。成功结果按 profile/桶缓存 5 分钟，只有仍匹配当前 quota generation、listing generation 与移动位置 epoch 的请求可以写入，迟到结果不会污染下一次桶列表。`go/storage/quota_cache.go` 把成功 `GetBucketQuota` 镜像进进程级 5 分钟缓存,key = 配额相关连接身份(协议/provider、endpoint、region、凭证、FTP 端口/匿名、path-style/JWan、代理)的 SHA-256——刻意排除显示、缓存、RootPrefix、挂载、写回、桶呈现设置,桶列表配置与挂载配置复用同一配额,而 endpoint/凭证变更隔离。命中/未命中日志只暴露短 hash 前缀。
- 未来远端配额保持可选并与自定义显示值区分来源;不支持的 provider 保持未知而不是报零;配额失败不得让桶加载失败。
- 测试:`test/bucket_quota_test.dart`、`test/widget_test.dart`(UI 复用)、`go/config/config_bucket_settings_test.go`、`go/mount/mount_capacity_test.go`、`go/mount/winfsp_statfs_windows_test.go`、`go/storage/quota_cache_test.go`、`go/mount/webdav_quota_test.go`。

**Known P2/P3 (review 2026-08-30):** P2 首启保存职责拆入 `config_setup_save.dart` 后，远端轮询、FTP/SFTP 文件集与新增后端指南一度遗漏新 part；已在同批更新 [mount_external_sync](mount_external_sync.md)、[storage_backends](storage_backends.md) 与 [AddingStorageBackends](../AddingStorageBackends.md)，评审过程见 [PROJECT_GUIDE](../PROJECT_GUIDE.md)。

**Known P2/P3 (review 2026-08-31):** P2 迟到的配额响应曾能覆盖页面会话的 5 分钟缓存（不影响当前列表，但下一次重载会复用旧数值）；缓存写入现与主列表 generation 和移动位置一起门控。
