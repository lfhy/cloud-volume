# Code Map — 特性域索引

每个特性域一行摘要;文件集、职责、数据流、binding 契约与 gotcha 在对应 `features/*.md`。动手前先读 [AGENT_GUIDE.md](AGENT_GUIDE.md) 的必读顺序;新探索先查 [PROJECT_GUIDE.md](PROJECT_GUIDE.md) 已有结论。

## 挂载与元数据核心

| 域 | 职责摘要 |
|---|---|
| [mount_metadata_core](features/mount_metadata_core.md) | 持久 inode bbolt 元数据 + journal + worker;挂载/页面共享单一 inode 视图(M2–M7);chunk 持久化契约、reset guard、崩溃恢复;三大 binding 不变式的前两条在此。 |
| [remote_tasks](features/remote_tasks.md) | 统一 `RemoteTask` 投影与任务列表首页可见性契约(排序/分页/历史 pager)、调试端点(`CV_DEBUG_ADDR`)、任务行视觉与 `RemoteTaskDetails`、`TransferQueue` 执行兼容层。 |
| [mount_queues_legacy](features/mount_queues_legacy.md) | 无 `ProfileID` 回退挂载的四队列写回体系(writeback/dirSync/rename/delete)、Finder 数据流、卡死与持久化已知风险。 |
| [macos_webdav_mount](features/macos_webdav_mount.md) | macOS 回环 WebDAV 本地优先写、Finder PROPPATCH/临时文件处理、配额投影、`mount_webdav` 同步生命周期与 URL 精确探测、孤儿挂载清扫。 |
| [mount_external_sync](features/mount_external_sync.md) | 页面/桥接 mutation 成功后的挂载缓存失效(`NotifyExternal*`)与 P0 远端目录轮询(活动跟踪 + 有界空闲刷新)。 |

## 账号与文件管理

| 域 | 职责摘要 |
|---|---|
| [account_management](features/account_management.md) | 账号管理页/三步向导(字段与 OAuth 职责拆分)、账号禁用、首启配置(页面/保存职责分层)、桶可见性与别名、每桶配额与远端配额发现、自定义排序、多账号桶加载韧性(并发/超时/singleflight/负缓存/3s 拨号超时)。 |
| [file_actions](features/file_actions.md) | 复制/移动目录选择、本地粘贴/拖拽上传(macOS Cmd+V channel)、预览缓存索引(bbolt)与上传播种、S3 软删除回收站与 item 阶段进度。 |
| [file_sync_p2p](features/file_sync_p2p.md) | 本地↔远端目录同步(三视图对账、删除推断、重命名检测)与 LAN P2P(mDNS 多账号发现、QUIC 传输、事件/内容安全,默认关闭)。 |

## 桌面应用壳与 UI

| 域 | 职责摘要 |
|---|---|
| [app_shell](features/app_shell.md) | 窗口关闭/托盘退出确认、macOS 窗口生命周期与常量、导航结构(桌面侧栏、Android 文件首屏 + 可配置底栏 + 返回栈)、桌面/Android 分离的桶与对象紧凑列表呈现层及共享运行时、应用图标生成链、响应式页面头部操作区。 |
| [mobile_ui](features/mobile_ui.md) | Android/移动端 UI 的跨特性设计检查清单：信息层级、48dp 触控、列表状态反馈、安全区/系统栏、底栏/Back、抽屉与无障碍；移动 UI 改动前必读。 |
| [ui_rules](features/ui_rules.md) | Flutter 组织规范、hover 可点击行 binding(StatefulWidget + `_hovered` + 中性洗色)、`AppLoadingIndicator` 分档、设置卡视觉一致性。 |
| [app_modal](features/app_modal.md) | 统一拟态框(`showAppModal*` 唯一入口、`AppShadDialog` Android 底部抽屉/桌面有限宽)与全量模态清单;远端目录选择器的精确初始目标及 fill-height/窄屏布局;debug 桌面子窗口壳(`DesktopModalSubWindowApp`、内容自适应缩放)。 |
| [settings](features/settings.md) | 设置页两栏锚点布局、四级诊断日志、应用内自动更新(镜像规则/完整性校验/续传重试/Windows 绿色 ZIP)、全局与每账号代理、远端配置备份与首启还原(单根备份别名与真实桶 identity 分离)。 |

## 平台

| 域 | 职责摘要 |
|---|---|
| [windows_platform](features/windows_platform.md) | 崩溃监视器/启动报告、自绘窗口与 DWM 圆角、Cloud Files/WinFsp/WebDAV 挂载呈现与盘符、Cloud Files 外部删除投影与持久 mutation journal、WinFsp 虚拟卷引擎(构建/安装/容量)。 |
| [windows_dev](features/windows_dev.md) | Windows 新机依赖引导与运行/构建脚本(ARM64 CLANGARM64 工具链、CargoKit/Rustup、CPATH、Developer Mode)。 |
| [android_dev](features/android_dev.md) | macOS/Windows Android 工具链引导、c-shared 桥构建、macOS 模拟器调测回路(`make android-run`)与 ARM64 APK 打包、应用 ID/私有数据边界、移动端桌面能力裁剪。 |

## 后端

| 域 | 职责摘要 |
|---|---|
| [storage_backends](features/storage_backends.md) | `go/jwanfs` FGW SDK(网关发现/故障转移/检测缓存)与 FTP/SFTP 后端(虚拟桶、递归删除、tracked upload、host-key 边界)。新后端指南:[AddingStorageBackends.md](AddingStorageBackends.md)。 |

## 仓库布局速览

- `lib/` — Flutter 前端(按类型分层:`app`/`pages`/`widgets`/`services`/`state`/`utils`/`theme`/`bridge`/`models`)。
- `bridge/` — 桌面 FFI 桥(c-shared Go 库,JSON 方法分发)。
- `go/` — 共享 Go 包:`mount`(挂载与元数据)、`storage`(后端抽象)、`s3`/`jwanfs`/`sync`/`p2p`/`config`/`webapi`/`logging`。
- `cmd/` — 独立可执行(cloud-volume-cli、cloud-volume-updater、cloud-volume-crash-reporter)。
- `macos/` `windows/` `linux/` `android/` — 平台 runner。
- `scripts/` — 构建/引导/打包脚本。
- `docs/` — 本文档体系;`third_party/` — vendored 插件 fork 与 WinFsp 头。
- 运行时状态:`~/.cloud-volume/`(config.db、metadata/v1、mounts、runtime/logs/bridge.log)。
