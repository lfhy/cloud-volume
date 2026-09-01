# Settings — 设置页、诊断日志、自动更新、代理与配置备份

## 设置页布局

两栏锚点布局:左垂直锚点栏轨(通用/Windows/关于 分组头),右滚动页一列展示全部设置卡。点左栏条目滚动右页到对应卡。栏轨**无持久 active/选中高亮**——条目只在 hover 时变化外观(点击不再钉住高亮)。

- `lib/pages/settings_page.dart` — `SettingsPage` + state。`_SettingsTab` 枚举标识每个配置块一卡/一锚。state 持有 `_contentScrollController` 与 `_sectionKeys`(**无 `_activeTab` 字段**)。`build()` 渲染 `Row`:左 `SizedBox(width: 180)`(标题 + `_buildGroupRail(theme)`),右 `Expanded` + `SingleChildScrollView(controller:)`(`_buildAllContent`)。
- `lib/pages/settings_page_layout.dart` — part 文件。`_SettingsLayout` 扩展:`_railGroups()` 构建 `_SettingsRailGroup`(分组头 + 锚点);`_buildGroupRail` 渲染分组头 + `_SettingsGroupTile` 行;`_tabLabel` 枚举→中文标签;`_buildAllContent` 经 `KeyedSubtree` + `_sectionKeys` 渲染每张可见卡;`_scrollToAnchor` 用 `Scrollable.ensureVisible` **只滚动**,不更新任何 active 状态。`_SettingsGroupTile` 是 hover-aware StatefulWidget tile(hover binding 见 [ui_rules](ui_rules.md)),**无 `active` 参数**——外观仅 hover。
- `lib/pages/settings_page_sections.dart` — part 文件。`_SettingsSections` 扩展,按锚点的卡构建器(更新/代理/外观/日志/下载/缓存/可见性/同步/回收站/WebDAV/重置账号/配置管理/Windows 写回/Windows 挂载/关于)。
- `lib/widgets/settings_mobile_nav_section.dart` — 「底部导航」卡体(常规组,**仅 Android 渲染**,gating 在 `_railGroups` 的平台条件里):每项开关(显示/隐藏)+ 上移/下移排序 + 恢复默认,变更即时持久化到 MobileNavPreferences(key `mobile.bottom_bar_items`,契约见 [app_shell](app_shell.md))并通知 main_layout 重建底栏;约束为 2–5 项且必须保留设置,旧首页不在可选池。失败时 toast 提示且不改状态。视觉遵循设置卡规范(顶部 muted 简介 + secondary 容器)。
- `lib/widgets/settings_cache_section.dart` — 缓存设置卡体。刻意分三个可见组:`缓存目录设置`(解析路径 + 选择/重置/打开)、`缓存占用`(统计块 + 刷新 + 错误文字)、`缓存清理`(手动清理按钮 + 自动清理规则编辑)。保持关注点视觉分离,不要合并回一个混合按钮行。
- `lib/pages/settings_page_actions.dart` — part 文件,`_SettingsPageActions` 扩展:全部配置保存/刷新/清理动作。

**数据流:** `_buildAllContent` 用与 `_railGroups()` 相同的可见锚点循环,每张卡包匹配 `_sectionKeys[tab]`;点 `_SettingsGroupTile` 调 `_scrollToAnchor(tab)` 滚到 keyed 卡,不设任何选中态。锚点列表高于视口时左栏独立滚动。设置卡的视觉结构规范见 [ui_rules](ui_rules.md) 设置卡一致性一节。

## 应用诊断日志

四级:`Silent`/`Error`/`Info`/`Debug`。设置界面用中文(安静/仅错误/常规/调试),持久化/桥接值保持小写英文。用户未选过时按构建模式默认:Debug 构建 `Debug`,Release 构建 `Silent`。

- `go/logging/logging.go` — 中央 Go 日志包:`Level`、进程级原子 level、`ConfigureOutput`、过滤 writer、`Debugf`/`Infof`/`Errorf`。存量 `log.Printf` 行按 `Info` 处理;含 error/failed/warn 的明显错误旧行保持 `Error`。新后端诊断用这个包,不要另加 logger 或 ad-hoc 过滤器。
- `bridge/logging.go` — 标准日志器经 `go/logging` 写 stderr + `BridgeLogPath()`(`~/.cloud-volume/runtime/logs/bridge.log`)。后端从 `Silent` 启动;Flutter 在 API bootstrap 后同步生效级别。
- `bridge/dispatch_log.go` / `dispatch.go` — 桥接方法:`set_log_level`、`get_log_level`、`write_flutter_log`(Flutter tag 行转发进同一过滤,前后端诊断共用一个级别)。
- `lib/utils/app_log.dart` — `AppLogLevel` + `AppLog.info/debug/error`;`AppBootstrapPage` 在 API bootstrap 后绑定。当前级别持久化在 SharedPreferences key `app.log.level`;`loadLevel()`/`setLevel()` 都调 `RemoteStorageGateway.setLogLevel`,设置同时作用于 Go 后端与 Flutter 转发日志。
- `lib/widgets/settings_log_section.dart` — 四级用户 UI(设置→通用→日志设置),可见文案不用 Flutter/bridge 等实现术语。
- Web no-op:浏览器构建不写桌面桥接日志文件。

**Release 日志排障提示:** `%APPDATA%\3000y\Yunjuan\shared_preferences.json` 无 `app.log.level` key 时 Release 构建保持桥接 `Silent`;`~/.cloud-volume/runtime/logs/bridge.log` 可能是零字节文件。要 Cloud Files 写回日志前,先确认设置里日志级别已显式改「调试」,受影响会话早于该改动时重启/重挂,并确认日志时间戳/大小推进后再复现。

## 应用内自动更新

检测新 GitHub release 并在桌面端应用内下载安装对应平台包——无需手动卸载或命令行。

### 关键契约

- **镜像规则:** GitHub Releases **API** 调用(`checkLatestRelease`)总是**直连** `api.github.com`——公共下载镜像(如 gh-proxy.com)对 api.github.com URL 返回 403。配置的镜像前缀(`UpdateNetworkConfig.wrapUrl`)只应用于 asset **下载** URL。
- **架构匹配:** 优先**运行构建架构**:Go 桥接 `get_build_info` 返回 `buildArch`(`-ldflags -X main.buildArch=...` 注入);Flutter 经 `widget.api.getBuildInfo()` 读取传给 `matchPlatformAsset`。桥接不可用(web、旧 dev 构建)回退 `runtimeCpuArchitecture`(解析 `Platform.version`)。特定架构包之后才试 universal。Windows:Dart 与 Go 匹配器都偏好精确原生 `yunjuan-windows-<arch>.zip`/installer 名;ARM64 可回退 amd64(Windows 11 ARM 支持 x64 模拟),amd64 绝不选 ARM64 包——精确文件名防桌面/CLI 包碰撞。
- **下载完整性:** 双重校验。(1) `verifyDownloadedSize`:下载并显式 `f.Close()` flush 后 stat,与 GitHub asset `size` 不一致删残留并报「下载文件大小不匹配……镜像可能返回了截断或错误内容」。(2) `verifyDownloadedDigest`:用 GitHub asset `digest`(`sha256:<hex>`)全文 SHA-256 校验,防同大小内容替换;空/非 `sha256:`/非 32 字节 hex 视为不可用摘要跳过不阻断。缓存命中路径也做大小+校验和校验,digest 不匹配跳过缓存重新下载。`probeDownloadURL` 带 `expectedSize`:镜像 HEAD 返回 `Content-Length > 0` 且与 `assetSize` 不一致时下载前直接拒绝坏镜像。
- **续传重试:** 单次下载抽成 `fetchOnce`,`downloadInstaller` 外层编排:`isRetryableFetchError` 判定(HTTP/2 stream error / connection reset / 意外 EOF 等)按已落盘字节数 HTTP Range 续传重试,最多 5 次(每次退避 attempt 秒,响应 ctx 取消);HTTP 状态码、写盘失败等不可重试错误立即返回。**不要**强制 HTTP/1.1(`ForceAttemptHTTP2=false`):某些镜像在该路径返回 HTTP/2 二进制帧,Go 按 HTTP/1.x 解析报 malformed response;保留默认协议协商 + Range 重试。相关超时:`checkLatestRelease` 每次尝试 30 秒、最多 3 次(2s/4s 退避,超时与可重试 socket 错误才重试);安装下载 HTTP client 上限 7200 秒(仍可经 `cancel_transfer` 取消);镜像 HEAD 探测 20 秒 client。
- **进度:** 服务端无 `Content-Length` 且 asset 无 size 时,`_installProgress` 初始化 `-1`(不定态),`LinearProgressIndicator` 用 `null` value,状态文字显示已下载字节。
- **任务类型:** Go 快照 `type: "app_update"`;Dart `TransferKind.appUpdate` 在 `_transferKindFromName` 与 `_kindFromWire` 都映射,标签「应用更新」,行图标 `refreshCw`,`displayName` 用 asset 文件名。
- **安装器缓存 + 续传:** 安装器在 `<ResolveCacheDir>/app_updates`;`UsableCachedInstaller` + Dart 传 `assetSize` 命中缓存跳网络(`statusDetail` `cached`);`downloadInstaller` 用 `Range: bytes=N-` 续传(206 追加,200 无 Range 时重启文件)。`installApp` JSON 带 `config` + `assetSize` + `assetDigest`。
- **Windows 绿色 ZIP 更新:** `matchPlatformAsset` Windows 优先 `yunjuan-windows-amd64.zip`,仅 ZIP 缺失才回退 installer.exe。`installWindowsZip` 从下载 zip 解出 `cloud-volume-updater.exe` 到临时目录并带 `-zip -install-dir -pid -exe-name` 启动(旧版本无需预装 updater)。watched 构建中 PID 是运行中的 `cloud-volume-app.exe` 但 `-exe-name` 是公共 `cloud-volume.exe` 启动器。updater 等 app PID、再轮询启动器也退出且可写后替换 staged bundle 并启动新启动器。updater 自 v1.2.0 起无窗口无消息泵(`updater_window_windows.go`);失败只在 `%TEMP%\cloud-volume-updater-<pid>.log` 可见。桥接有意在外部 updater 替换锁定文件前退出主应用,无头 updater 失败在用户感知上是应用消失或不重启。updater EXE 由 `run_windows.ps1 -Build` 与 `build_desktop_packages.sh build_windows` 构建,随 release zip 发布供更新时按需解出。启动器/崩溃报告器配合见 [windows_platform](windows_platform.md) 崩溃监视器一节。
- **重启:** `relaunchApp` macOS 启动 `/Applications/云卷.app`(bundle 本身,不是裸可执行文件),让 LaunchServices 拥有新应用生命周期。
- **镜像探测 UI:** 镜像字段带「测试镜像可用性」按钮:取最新 release 首个 `browser_download_url`,套所选前缀 HEAD 探测,内联显示 2xx/3xx/4xx 结果,用户触发更新前先选可用镜像。`SettingsUpdateMirrorField` 用 `didUpdateWidget` 在父级传入变化的 `mirrorPrefix` 时重新解析 `_mode` 并清探测状态(异步加载的镜像配置到达时首帧不能停在 direct)。

### 关键文件

- `lib/services/app_update_service.dart` — `checkLatestRelease`(直连 GitHub API,解析 `tag_name` + assets);`ReleaseAsset` 带 `name`/`downloadUrl`/`size`/`contentType`/`digest`;`compareVersionLabels` 语义化版本比较。
- `lib/services/platform_asset_matcher.dart` — `matchPlatformAsset(assets, {runtimeArchitecture})`:macOS 特定架构 DMG/zip → universal → 其它架构;Windows `.zip` → `installer.exe`;Linux `.AppImage` → `.tar.gz`。Dart(`test/platform_asset_matcher_test.dart`,带 test-only 平台覆盖)与桥接(`bridge/dispatch_platform_asset.go` + `dispatch_platform_asset_test.go`)双侧实现同一顺序。
- `lib/services/app_installer.dart`(条件导出 io/stub)/ `app_installer_io.dart` — 桌面委托 `api.installApp()` → 桥接 `install_app`;进度经传输监控投进 `RemoteTaskStore`(无 Dart `Process.run`/下载)。`app_installer_stub.dart` / `app_installer_web.dart` — Web stub 返回错误串(浏览器无本地文件系统)。
- `bridge/dispatch_app_install.go` — Go `install_app`:下载(镜像/代理)、平台安装(DMG/ZIP/exe/AppImage/tar)、重启、`os.Exit(0)`;后台 goroutine + `taskId`。Windows installer EXE 静默 Inno Setup;ZIP 走 updater。`probeDownloadURL` 下载前 HEAD 探测(带 expectedSize 检查)。用 `storageconfig.ProxyHTTPClient`,不强制 HTTP/1.1。
- `bridge/app_install_download.go` — 可续传下载、重试编排、缓存目录解析、下载后完整性校验(大小 + digest);缓存复用前重新校验 digest。测试 `bridge/app_install_download_test.go`。
- `bridge/windows_process_attrs_windows.go` / `_other.go` — 隐藏启动 Windows ZIP updater 的小平台 shim。
- `cmd/cloud-volume-updater/` — 独立 Go updater:`main.go`(参数解析、`performUpdate` 编排)、`process_windows.go` / `process_other.go`(等旧 PID、轮询可写、确认新进程)、`logger.go`(`%TEMP%\cloud-volume-updater-<pid>.log` 时间戳日志,每次 logf flush)、`updater_window_windows.go`(Windows 无头 wrapper)/ `updater_window_other.go`(非 Windows stub 供 go vet 交叉编译)。
- `bridge/build_info.go` — `buildArch` 包变量(ldflags 注入)+ `get_build_info()`;本地 dev 构建回退 `runtime.GOARCH`。
- `lib/platform/platform_info_io.dart` / `_stub.dart` / `_web.dart` — `runtimeCpuArchitecture` 启发式。
- `lib/widgets/settings_update_section.dart` — 更新 UI(设置→通用→应用更新):版本状态、检测更新、一键更新、取消更新(`RemoteTaskStore.cancel(taskId)` → 桥接 `cancel_transfer`)、不定/百分比进度条、GitHub 下载回退。取消能力遵循安装器边界(见 [remote_tasks](remote_tasks.md) 显示链路)。
- `lib/widgets/settings_update_mirror_field.dart` — 镜像输入(从 `settings_update_section.dart` 拆出保持 500 行内);持久化经 `UpdateNetworkConfig`(SharedPreferences key `flutter.update.mirror_prefix`),只影响下载 URL。
- `lib/bridge/remote_storage_bridge.dart` — `_findBundledLibraryPath()` macOS 顺序 **Frameworks → MacOS**:bundle 可能同时含 `Contents/Frameworks/`(make build-macos)与旧 dev 运行的 `Contents/MacOS/` 陈旧 dylib 副本;先探测 Frameworks 防止加载无 `install_app` 的旧库。`Makefile` `build-macos` cp 前先 `rm -f` MacOS 副本。

### 数据流

检测更新 → GitHub API 直连 → 匹配资产(`runtimeArchitecture: _buildArch`)→ 一键更新 → `api.installApp(...)` → 桥接 `install_app` 后台 goroutine 流式下载(镜像套下载 URL;配代理时系统模式先 `resolveSystemProxy`)→ 传输监控报进度 → Flutter 渲染匹配的 `RemoteTaskStore` 任务 → 下载完成按平台安装(macOS 挂 DMG 替换 /Applications/云卷.app;Windows 静默 exe 或 ZIP updater;Linux 替换 AppImage/解 tar)→ `relaunchApp()` + `os.Exit(0)`。

## 网络代理(全局 + 每账号)

三种全局代理模式:system(默认)、direct(无代理)、custom(自定义 URL)。影响全部出站流量。每账号可再选独立策略,默认 `inherit`(跟随全局);显式选项为 `system`、`direct`、`custom`(HTTP/SOCKS5,可带认证)。全局代理独立持久化在 bbolt `meta`,只作为继承账号的回退。

### 关键文件

- `go/config/config.go` — `ProxyModeInherit` 与四种账号模式归一化;新账号默认 `inherit`。
- `go/config/global_proxy.go` — bbolt `meta/global_proxy` 持久化全局代理子集(`LoadGlobalProxy`/`SaveGlobalProxy`)。全局模式自身不能 `inherit`,归一化为 `system`。
- `go/config/proxy.go` — `ProxyTransport(mode, customURL)` 返回尊重模式的 `http.RoundTripper`;`ProxyHTTPClient` 包超时。`ResolveProxyConfig(account, global)` 仅在账号模式 `inherit` 时拷贝全局字段,显式 system/direct/custom 账号不动。
- `go/storage/types.go` — `ForConfig` 加载全局代理、解析继承、用有效配置构造 S3/WebDAV/Baidu backend。
- `go/s3/client.go` — AWS S3 客户端用 `ProxyTransport`;`go/s3/minio_directory.go` — MinIO `options.Transport`。
- `go/storage/webdav_backend.go` — WebDAV `http.Client` 经 `ProxyHTTPClient`。
- `go/storage/baidu_pan_sdk.go` / `baidu_pan_retry_http.go` — 每账号 xpan HTTP client(有效代理 transport + 每账号 OAuth 凭证);全局 xpan client 仅作 legacy 回退。`ApplyBaiduPanProxy` 在配置保存时应用。
- `bridge/dispatch_config.go` — `update_proxy_settings` 只写独立全局代理记录,**不**覆盖每个 profile(不要恢复循环覆盖全部 profile 的旧行为——那会摧毁每账号覆盖);bootstrap 返回全局代理字段给设置页。
- `bridge/dispatch_system_proxy.go` + `dispatch_system_proxy_windows.go` / `_other.go` — `resolve_system_proxy`:读 Windows 注册表 `HKCU\...\Internet Settings`(`ProxyEnable`/`ProxyServer`),其它平台返回空。`lib/models/system_proxy_info.dart` 镜像。
- `lib/services/proxy_http_client.dart` — 条件导出:IO → `proxy_http_client_io.dart`(dart:io `HttpClient` 带代理),Web → stub(浏览器自理)。
- `lib/services/update_settings.dart` — GitHub 镜像配置(与代理分开):SharedPreferences 持久化,给 github.com 下载 URL 套镜像前缀。
- `lib/widgets/settings_proxy_section.dart` — 全局代理 UI:模式 chips + 自定义 URL + GitHub 镜像快捷选择;文案说明账号可覆盖。
- `lib/widgets/account_proxy_section.dart` — 账号编辑器代理 UI:跟随全局/跟随系统/直连/自定义;自定义展开 HTTP/SOCKS5 host/port/auth 字段。
- `lib/widgets/cloud_storage_account_dialog.dart` — 为 S3/WebDAV/Baidu 嵌 `AccountProxySection`,随草稿提交代理值。
- `lib/models/cloud_storage_account_draft.dart` / `lib/utils/account_config_builder.dart` / `lib/models/remote_storage_config.dart` — 携带并序列化每账号代理;新账号默认 `inherit`。
- `github.com/lfhy/xpan`(go.mod 当前 v0.1.6)— 每调用 HTTP client 与每 `Client` 凭证的 SDK 能力,使并发百度账号不在全局 token 上竞争;多账号凭证支持需要 v0.2.0 及以上,升级前先确认依赖已发布。

### 系统模式注意(binding)

Dart 的 `HttpClient.findProxyFromEnvironment` 只读 `http_proxy`/`https_proxy` 环境变量,**忽略 Windows 设置里的手动代理**。桌面应用经 `resolve_system_proxy` 读宿主级系统代理(Windows 注册表);更新检查与安装下载前,设置更新区先调 `api.resolveSystemProxy()` 把 Windows 注册表代理转成 custom `ProxyConfig`——「跟随系统」模式才真正尊重 Windows 代理。Go 侧 `ProxyTransport` 对 S3/WebDAV/Baidu 流量仍用 `http.ProxyFromEnvironment`。

### Gotchas

- `direct` 是合法的每账号覆盖:即使全局代理是 custom,该账号也不走代理。
- 每账号代理字段参与配额缓存 key(`go/storage/quota_cache.go`,见 [account_management](account_management.md))。

## 远端配置备份

应用可把当前账号配置保存为加密远端快照,误改配置后从设置页还原;备份目标不属于普通账号列表时也可独立保存。

- `go/config/config_backup.go` — bbolt `meta` 保存 `ConfigBackupSettings`;目标可引用 profile 或保存独立 `RemoteStorageConfig`。`ExportConfigBackup`/`RestoreConfigBackup` 只处理 profiles、活跃账号、全局代理、显示顺序,刻意不打包本地缓存;还原保留备份目标设置。
- `go/config/config_db_shared.go` / `config_db_shared_test.go` — 所有运行时配置读写经同一进程级 `config.db` bbolt 句柄取得 lease；Android 私有数据根目录切换等待未完成 lease 后再关闭旧句柄，同一路径重设不打断现有调用。回归覆盖共享句柄、根目录切换、重复还原、并发轮询读取与 `tx.Check()` 完整性检查。
- `go/configbackup/backups.go` — 解析目标,用用户自设备份密码派生 AES-GCM 密钥(`cloud-volume/config-backup/v2` + password 的 SHA-256),上传/列举/下载 `*.cloud-volume-config.json.enc` 快照。恢复前校验前缀、后缀、最大 32 MiB,再验证解密标签并导入。空密码走明文 JSON;加密但无密码返回 `此备份已加密,请先设置加密密码`,密码错误包装为 `无法解密配置备份:...`。
- `bridge/dispatch_config_backup.go` — 加载/保存目标、立即备份、列快照、还原;`restore_config_backup_with_target` 成功后把 inline target(含密码)固化为本地备份设置并默认开启自动备份。普通 profile/代理/排序变动以及后台百度网盘 OAuth token 刷新都会进入同一个 2 秒合并窗口异步自动备份,远端失败不阻塞本地保存;若刷新发生在备份上传期间,队列会在当前轮次结束后补传一份包含新 token 的快照。
- `lib/models/config_backup.dart` / gateway — Flutter 模型/API;Web 明确不支持本地配置备份。
- `lib/utils/bridge_error_text.dart` / `test/config_backup_restore_test.dart` — `isConfigBackupDecryptionError` 只匹配 Go 稳定解密失败文案(`无法解密配置备份`/`此备份已加密`/`message authentication failed`),网络/解析错误不误进密码重试。
- `lib/widgets/config_backup_restore.dart` — 共享密码输入弹窗 + 解密失败重试循环;`skipInitialAttempt` 用于「本地密码已经失败过」路径;取消抛 `ConfigBackupRestoreCancelled`,调用方静默退出。
- `lib/widgets/settings_config_backup_section.dart` / `settings_config_backup_target.dart` / `settings_config_backup_location_picker.dart` / `settings_config_backup_encryption.dart` / `settings_config_backup_cards.dart` / `settings_config_backup_history_dialog.dart` / `settings_config_backup_labels.dart` + 设置页/首启页 — 「设置→账号→配置备份」配置目标、自动备份与立即备份;页面只保留可点击的历史摘要卡,完整快照列表在 `ConfigBackupHistoryDialog` 拟态框滚动查看。还原流程:点还原 → 立刻确认 → 用本地密码尝试 → 解密失败才弹密码框循环重试。历史弹窗后台刷新不锁行按钮(否则首点被吞——`busy` 只含 `_restoring/_deleting`,不并 `_loading`)。首启「从备份存储还原」复用同一密码重试 helper;快照加载显式区分 loading/error/empty,成功空列表显示目录提示而不保留 spinner。独立目标复用账号连接向导但不调 `saveProfile`,因而不出现在账号页。
- `lib/utils/config_backup_picker.dart` / `lib/widgets/settings_config_backup_location_picker.dart` / `lib/pages/config_setup_restore.dart` / `lib/widgets/remote_directory_picker_dialog.dart` / `test/remote_directory_picker_dialog_test.dart` — 设置页与首启独立备份存储共用 picker 展示模型。WebDAV、百度网盘、FTP、SFTP 的单个合成桶显示别名「备份存储」;`BucketInfo.name`、entry id、确认结果与持久化 target 保留真实 bucket identity。设置页已保存路径预览按目标的存储类型使用同一别名，打开时仍精确传回已保存的 raw bucket + prefix；仅无已保存位置的新单根目标用真实桶 + `prefix: ''` 自动进入。S3 即使只有一个桶也保留真实桶名并停在桶列表。空/失效目标不把默认 `cloud-volume-config-backups` 前缀套进任意首桶;通用 picker 的精确初始目标、窄屏行/动作区和错误恢复契约见 [app_modal](app_modal.md),理由见 [Agent Note](../notes/implemented/bug-fix/2026-08-30-android-backup-directory-picker.md)。

**Gotchas:** 加密密钥只从用户备份密码派生,与 endpoint/AK/SK 无关,换机器可解密;密码错误与未设密码是两类稳定错误,UI 只对它们弹密码框。自动备份只在已存在且启用的目标上运行,多个紧邻本地配置写入合并为一次快照。完整清除本地配置后,必须先重新提供备份目标连接才能读远端快照,不能从加密备份无凭证自举。
