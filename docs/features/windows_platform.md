# Windows Platform — 崩溃监视、自绘窗口、挂载呈现与两个挂载引擎

覆盖:发布包崩溃监视器/启动报告、自绘窗口与 DWM 圆角、Cloud Files/WinFsp/WebDAV 三种挂载呈现与盘符、Cloud Files 外部删除投影与持久 mutation journal、WinFsp 虚拟卷引擎。窗口关闭/托盘退出流程见 [app_shell](app_shell.md);开发环境脚本见 [windows_dev](windows_dev.md)。

## 崩溃监视器 / 启动报告

Windows 发布包把公共启动器与 Flutter 进程分离,首窗口存在之前的失败也可观察。

- `windows/runner/crash_launcher.cpp` — 公共 `cloud-volume.exe`。解析同级 `cloud-volume-app.exe`,转发原始命令行,`CreateProcessW` 启动并等待其进程句柄;非零退出或创建失败后启动报告 helper。报告 helper 本身不可用时,用原生弹窗显示 Windows 错误/退出码。它只导入 Windows 系统库、无 Flutter/Go 运行时依赖——连自身无法加载之外的损坏都能诊断。
- `windows/CMakeLists.txt` / `windows/runner/CMakeLists.txt` / `windows/runner/Runner.rc` — Flutter 目标名 `cloud-volume-app`;小原生 `cloud_volume_launcher` 目标保持磁盘名 `cloud-volume.exe`;Go `cloud-volume-crash-reporter.exe` 以 `CGO_ENABLED=0` 构建并安装到两者旁。启动器以 UTF-8 编译(最后手段的原生错误含中文)并静态链接 MSVC 运行时(缺 `MSVCP140`/`VCRUNTIME140` 不能阻止监视器自身启动)。
- `cmd/cloud-volume-crash-reporter/main.go` / `report.go` / `notify_windows.go` — 解析启动/退出诊断,写 `~/.cloud-volume/runtime/crashes/crash-<timestamp>-<pid>.txt`(用户权限)并提供 Explorer 里显示。报告含 Windows 版本、运行时架构、签名/十六进制退出码、启动器/Flutter 应用/`data/app.so`/桥接的 SHA-256/大小/mtime,以及 `bridge.log` 与最新 `%TEMP%\cloud-volume-updater-*.log` 的 64 KiB 尾部;提示可能含本地路径。`report_test.go` 覆盖退出码/工件内容与有界日志尾。
- `bridge/app_launcher_path.go` / `bridge/dispatch_app_install.go` — Windows ZIP 更新把公共启动器传给 `cloud-volume-updater.exe`(Flutter 内 `os.Executable()` 解析为 `cloud-volume-app.exe`)。
- `go/mount/windows_process_cleanup_windows.go` / `lib/pages/settings_page_actions.dart` — 开发清理终止启动器与应用两个进程,UI 通用描述。
- `scripts/run_windows.ps1` / `build_desktop_packages.sh` / `build_windows_installer.ps1` — 发布打包校验启动器、应用、崩溃报告器、更新器齐全才出产物。

**数据流:** 安装器快捷方式/安装后启动/ZIP 用户/更新器启动 `cloud-volume.exe` → 启动器启动 `cloud-volume-app.exe` 并隐藏等待;Flutter 创建的模态/预览子窗口直接 spawn `cloud-volume-app.exe`,不包额外监视器。退出码 0 是正常(确认关闭与桥接更新时主动 `os.Exit(0)`),启动器静默退出。非零退出或创建失败启动报告 helper:指纹已装运行时、追加有界诊断尾、写报告、提示用户检查/提交。绿色 ZIP 更新:更新器等 Flutter PID 退出(0)后轮询 `cloud-volume.exe` 可写,替换整个 bundle 并启动新启动器。

**Gotchas:**
- **不要**把快捷方式/更新器重定向指向 `cloud-volume-app.exe`——那绕过首窗口前崩溃捕获。
- 退出码 0 **不是**崩溃:应用内更新器把工作交给外部 updater 后有意 `os.Exit(0)`。
- `cloud-volume.exe` 在应用健康期间保持运行,更新必须等两个进程后才覆盖启动器镜像;传启动器作 updater `-exe-name` 提供可写门控。
- 报告可能含日志里的本地路径:保留用户审阅警告与 64 KiB 尾上限;不收集凭证或完整配置文件。

## 自绘窗口 / DWM 圆角

Windows 宿主移除原生标题栏用自绘 chrome,同时在 OS 支持处向 DWM 请求原生圆角。

- `windows/runner/win32_window.cpp` — 以 Flutter 默认 `WS_OVERLAPPEDWINDOW` 创建主宿主,`WM_SIZE` 中调整承载的 Flutter 子窗,`UpdateTheme` 请求原生圆角。不覆盖非客户区计算、hit-testing 或标准最小化/最大化/拖拽命令——注册的 `window_manager` 插件拥有这些行为。
- `windows/runner/flutter_window.cpp` — 承载 Flutter 视图并拥有项目特定的托盘/关闭/退出行为。自定义 method channel 不再暴露最小化/最大化/拖拽/最大化态方法(Windows 上 `window_manager` 负责,Linux 保留自定义通道);初始可见性留给 Dart,首可见帧前窗口保持隐藏。
- `lib/app/app_entry_io.dart` — 初始化 `window_manager`,`runApp` 前对主 Windows 窗口应用 `TitleBarStyle.hidden`,Flutter 首帧后 show/focus。
- `lib/widgets/desktop_window_controls.dart` / `lib/services/window_controls.dart` — 自绘控件。Windows 常规最小化/最大化/拖拽/状态经 `window_manager`,`WindowListener` 事件保持最大化图标同步。

**Gotchas:**
- 原生 DWM 圆角是 Windows 11 代 shell 特性;Windows 10 / Server 2022 build 20348 上 `DWMWA_WINDOW_CORNER_PREFERENCE` 被忽略(编译通过),主窗口保持方角。当前代码请求圆角但无手动 `SetWindowRgn`/透明窗掩码回退。旧诊断机报 Server 2022 build 20348 时缺圆角是预期;2026-07-17 静态诊断在 Win11 Pro 26100 独立确认过相关代码路径。
- Windows 非客户区行为保持**单一 owner**:`window_manager` 已处理 hidden-titlebar `WM_NCCALCSIZE`、最大尺寸约束、帧刷新、原生系统动画。在 `Win32Window::MessageHandler` 重复这些会造成顺序冲突(插件 delegate 先于 runner handler)。
- 不要把主宿主样式换成 `WS_POPUP`、不要在最大化周围恢复 runner `ForceRedraw()`——前者丢标准任务栏工作区,后者只是给未绘制过渡重新上色。
- 窗口类必须保留真实 `hbrBackground` 刷子(`CreateSolidBrush(RGB(0xF8,0xFA,0xFF))`,匹配浅色应用表面):`hbrBackground = 0` 时最大化/还原暴露区闪黑直到 Flutter 呈现新帧。分层/透明窗不可行——承载的 Direct3D Flutter 子窗无法透过它合成,表面匹配的不透明刷子是可靠修复。出深色主题时刷子颜色必须跟随。

## 挂载呈现 / 盘符

两种呈现:Cloud Files 恒为 sync-root 目录;WinFsp 是给桶真实盘符与容量报告的虚拟卷引擎。

- `go/mount/backend_windows.go` — 选择 `cloud_files_cached`、`cloud_files_direct` 或 `webdav`;空/未知设置归一化为 `cloud_files_cached`。
- `go/mount/backend_windows_webdav.go` / `webdav_mount_windows.go` — WebDAV 启动本地服务器,从 `Z:` 向下扫空闲盘符(到 `D:`),调 `net use <drive> <url> /persistent:no`。当前分配器不让用户指定盘符,总选 `Z:`→`D:` 顺序的最高空闲字母。
- `go/mount/backend_windows_cloud_files_cgo.go` / `windows_cloud_files_paths.go` — Cloud Files 在 `~/Cloud Volume/<bucket>` 注册稳定 sync root 并返回该目录为 `mountPath`。过期清理遇被占用缓存文件时注销 root 但保留目录,下次启动可安全复用。
- `go/mount/windows_drive_mapping_windows.go` / `windows_drive_mapping_other.go` — 共享盘符发现、请求字母校验、`subst` 生命周期与可移植桥接 stub。列 `Z:`→`D:` 空闲字母,挂载时再校验所选字母,创建后验证映射,移除前比较当前目标,只清理目标是 Cloud Files root 直接子项的托管映射。
- `go/mount/windows_shell_namespace_windows.go` — `windows_this_pc_entry_enabled` 为 true 时,Cloud Files 可在「此电脑」下注册每用户 Explorer 命名空间快捷方式——这是指向 sync root 的文件夹条目,不是 `X:` 式盘符。**Shell 刷新 gotcha:** 只有实际增删托管「此电脑」命名空间 key 时才调 `notifyExplorerShellChanged`;每次清理都广播 `SHCNE_ASSOCCHANGED | SHCNF_FLUSH`(包括无命名空间条目时)会在退出期间造成不必要的全桌面/Explorer 刷新。
- `bridge/dispatch_mount.go` / `lib/services/remote_storage_api_desktop_storage.dart` / `remote_storage_gateway.dart` — `list_available_drive_letters` 经可选 `AvailableDriveLetterQuery` 能力暴露 Windows 盘符列表,Web 与测试 gateway 不需要无意义的 Windows 方法。
- `lib/widgets/mount_bucket_dialog.dart` / `lib/pages/file_manager_page_mount.dart` — 读写开关是 `ShadSwitch`。Cloud Files 仅路径(Explorer 不会把宿主卷剩余空间当桶容量);仅 WinFsp 显示空闲盘符选择器并报告配置的桶容量。对话框打开前仍查询空闲盘符,切到严格只读 WinFsp 的用户可装驱动继续。WinFsp 引擎的桶在挂载前探测可用性并缺驱动时提供应用内安装确认模态。对话框改引擎时保存桶所属的命名 profile 而不是 `saveConfig`(那总是写 `default`)——防止非默认账号被克隆、刷新后显示重复桶。
- `lib/services/remote_storage_gateway.dart` / `lib/models/bucket_mount_status.dart` / `go/mount/options.go` / `types.go` — 请求的 `driveLetter` 进会话,实际 `driveLetter` 返回 Flutter;打开已挂载桶优先该盘符,provider 内部继续用真实 sync-root 路径。
- `lib/widgets/windows_settings_sections.dart` / `lib/models/remote_storage_config.dart` — 设置暴露两个 Cloud Files 变体与 legacy 纯 WebDAV 映射盘回退;新/默认配置选 `cloud_files_cached` 并禁用可选「此电脑」命名空间条目。
- 容量解析见 [account_management](account_management.md) 桶自定义配额节与下文 WinFsp。
- `go/mount/cloud_files_hydrator_windows.go` / `cloud_files_hydrator_placeholders_windows.go` / `cloud_files_provider_windows.go` / `cloud_files_provider_directories_windows.go` / `cloud_files_windows.c` / `cloud_files_windows.h` — 占位符 fetch 把回调路径映射回已校验虚拟前缀、列该远端目录、创建占位符;合并调用方收到 leader 的真实错误。已有保留缓存条目时,目录占位符以 `CF_UPDATE_FLAG_ENABLE_ON_DEMAND_POPULATION` 更新;普通 NTFS 目录以 `CfConvertToPlaceholder` + `CF_CONVERT_FLAG_ENABLE_ON_DEMAND_POPULATION` 转换,Explorer 请求其子项而不是当永久空目录。**不要**在 `CreatePlaceholders` 里简单跳过已存在目录:注销后保留目录可能丢失占位/按需态,必须原地修复使子项保持懒加载且本地文件不被丢弃。回归锚点:`cloud_files_hydrator_placeholders_windows_test.go`、`cloud_files_types_windows_test.go`;原生保留目录转换仍需 Explorer 重挂检查。
- `go/mount/windows_hidden_command_windows.go` — 挂载生命周期用到的每个控制台工具(`subst`、`net use`、`sc`、PowerShell)经 `hiddenWindowsCommand`(`HideWindow` + `CREATE_NO_WINDOW`),防止挂载/卸载/清理/确认退出时的控制台闪现。回归锚点 `windows_hidden_command_windows_test.go`。

**Gotchas:**
- **不要**把 Cloud Files「此电脑」命名空间项描述为盘符:`Win32_LogicalDisk`/`net use` 不含它,路径仍在用户 profile 下。
- **不要**在 UI 恢复 Cloud Files 盘符选择:`subst` 映射只是宿主目录别名,多桶挂载显示错误容量;需要承载容量的卷时用 WinFsp。
- 盘符 `ShadSelect` 设 `ensureSelectedVisible: false`:包默认对选中项 `Scrollable.ensureVisible`,popover 打开时会把周围应用模态滚到最后一行。
- 移除必须查询当前 `subst` 目标,拒绝删目标与会话路径不同的盘。每桶过期清理在删 sync root 前跑;全量清理只移除目标是 `~/Cloud Volume` 直接子项的映射。
- 被占用的 Cloud Files 缓存不是活跃挂载:provider 断开/注销后 `Stop` 保持桶未挂载,缓存移除问题经 `BucketMountStatus.lastError` 返回;`cleanupManagedWindowsCloudFilesForBucket` 保留删不掉的稳定 root 供下次挂载注册复用。`CleanupStaleWindowsProcesses` 只终止本地构建 runner 目录下的过期 `cloud-volume.exe`/`cloud-volume-app.exe` 进程,有意不终止占用打开文件的 Explorer、Office 等用户应用。

## Cloud Files 外部删除投影与持久 mutation journal

`NotifyExternalDelete` 同步 Go 侧 `bucketCache` 与物理 Windows Cloud Files sync root。`bucketAccess.MarkExternalDelete` 先取消 pending writeback 再放 tombstone,然后调用 Cloud Files 会话期间安装的投影器:移除 `Cloud Volume\<bucket>` 下本地文件/目录并记录短期 provider-delete 标记,fsnotify 与 `NOTIFY_DELETE_COMPLETION` 都把移除当 provider 持有,不调度重复远端删除。`InvalidateExternalUpload` 用匹配的上传投影器处理应用侧建目录、上传、复制、移动/重命名目的地:刷新远端元数据、按需重建被覆盖占位符,只在父目录已存在 sync root 时创建子项,否则下次占位符 fetch 创建缺失树。

文件与流程:`go/mount/bucket_access.go` 持有会话级 `externalDelete`/`externalUpload` 投影器;`bucket_access_reads.go` 从外部 mutation 失效进入时取消 pending writeback 并调用它们;`backend_windows_cloud_files_cgo.go` 安装/清除投影器并消费 provider-delete 回调标记;`cloud_files_external_delete_windows.go` 校验路径、移除占位符、读远端元数据、创建新/覆盖占位符;`cloud_files_watcher_state_windows.go` 持有 provider-delete 与普通 watcher 状态(watcher 生命周期测试拆在 `cloud_files_watcher_windows_test.go` 与 `cloud_files_watcher_lifecycle_windows_test.go` 保持行数)。文件删除链:`delete_object` → 远端软删 → 取消 writeback → 缓存 tombstone → 本地占位符移除。目录创建/上传/复制/移动:`NotifyExternalUpload`/`NotifyExternalRename` → 缓存失效 → 远端元数据查 → 本地占位符创建。Explorer 删除仍是 CFAPI delete completion → `handleDelete` → `deletePath` → 异步远端删除。

- **回收站恢复投影:** `restore_trash_item` 从 Flutter 经 `bridge/dispatch_trash.go` 携带 `TrashItem` 原 key/目录标志,backend 恢复后调 `NotifyExternalUpload`——清除挂载 tombstone 并重投影 Cloud Files 占位符,恢复→再删/改名不依赖重挂。
- **只读拒绝:** Cloud Files 只读模式在桥接侧拒绝——CFAPI 收到 post-operation 回调无法否决 Explorer 写入;`mount_bucket_dialog.dart` 把严格只读选择路由到 WinFsp(其文件系统方法返回 `EROFS`)。
- **卸载确认:** 提供保留/清除托管默认 Cloud Files sync-root、警告打开文件;`backend_windows_cloud_files_cgo.go` 报告被占用的缓存清理而不重挂已断开卷。

### Explorer 上传后目录重命名(异步屏障)

Cloud Files 重命名回调经 `backend_windows_cloud_files_cgo.go` 与 `bucket_access_writes.go` 入队异步写回屏障。`writeback_rename_queue.go` 分配上传 generation:目录重命名前的上传先排空,重命名重试至成功,新路径下观测到的上传在该屏障完成前不能开始。`writebackQueue` 把排队与 in-flight 本地源路径从旧目录重基到新目录,保留原远端 key——后端顺序为 上传旧 key → 重命名 → 上传新 key。`MarkRenameSource` 只抑制过期旧路径 watcher 事件,不让重命名树永久 hydrating。队列停止信号同时用于两个分发器,关机不会向已关闭上传 channel 发送。回归:`writeback_rename_queue_test.go`、`cloud_files_watcher_windows_test.go`。

跨客户端变更诊断:`cloud_files_watcher_windows.go` 只同步到 stage 本地状态与入队工作;`backend_windows_cloud_files_cgo.go` 把目录重命名路由进 `bucket_access_writes.go`、文件移动进 `enqueueRenamePath`,CFAPI 回调保持非阻塞;`overlay_bridge.go` 把 staged 目录标记送 `dir_sync_queue.go`,文件上传与远端移动共享 `writeback_rename_queue.go`。

### 目录顺序(回归锚点:`dir_sync_queue_test.go`、`bucket_access_remote_probe_test.go`、`writeback_rename_queue_test.go`)

`writeback_rename_queue.go` 先排空目录重命名前捕获的上传 generation,等 `dirSyncBarrier`,再跑远端重命名,最后释放后续上传。`dir_sync_queue.go` `rebaseAndFence(old,new,isDir)` 把每个排队 old-prefix 创建 rekey 到新 prefix,已运行的 provider 调用保持原路径,目标碰撞通过屏障内保留两个条目解决,每个条目在其 provider 调用完成后才关闭。重基目录创建的旧源被证实缺失时,`bucket_access_writes.go` 探测旧路径、调幂等 `createRemoteDirectory(newClean)`、验证目的地标记,仅在新路径存在后跳过 `MoveObject(old,new)`。只有 `os.ErrNotExist` 表示缺失;认证、网络、listing 错误传播并保持重命名可重试。

### 重启安全的远端移动(mutation journal)

每个排队远端移动持久化为 append-only、逐事件 fsync 的 JSONL 记录,在 `<sessionRoot>/mutations/queue-<pid>.jsonl`。回归锚点:`mutation_record.go`、`mutation_store.go`、`mutation_reconcile.go`、`mutation_test_backend_test.go`、`mutation_store_test.go`、`writeback_mutation_recovery_test.go`。

- `mutation_record.go` `mutationRecordVersion` 门控前向兼容;`mutationEventUpsert`/`mutationEventComplete` 是仅有的 journal 种类。
- `mutation_store.go` 容忍每文件恰好一条未终结尾行(追加中崩溃);内部畸形数据与不支持的版本是硬错误,绝不静默复活或丢弃移动。恢复按文件顺序重放每个 `queue-*.jsonl`,把活记录压缩进唯一命名 JSONL,最后移除过期进程日志(Windows 上不复用已存在文件名)。
- `bucket_access.go` 持 `writebackQueue.mutations`;`writeback_restore.go` 在任一分发器启动前重建上传屏障与本地源重基,并把下一队列 generation 推过最大恢复 generation。
- `mutation_reconcile.go` 状态驱动重试矩阵:源缺失+目的地存在 → 无 provider mutation 标完成;源存在+目的地缺失 → `MoveObject`;两者都在 → `CopyObject` + `DeleteObjectHard` 合并;两者都缺 → 保留为 state-conflict。真实 provider 成功仍需验证后置条件(源探测缺失、目的地探测存在)才写 `Complete`;provider 成功与 tombstone 间崩溃可恢复——下次对账看到 源缺/目的在 收敛。只有 `os.ErrNotExist` 表示缺失;认证、网络、超时、listing 错误传播保持重试。`mountSession.status()` 读 `writebackQueue.mutationLastError()`,持久失败无需内存回调即可浮出。

### 有界空闲目录刷新

`directoryActivityTracker` 是上限 `remotePollDirectoryCap = 12` 的有界观测目录集。空闲条目不被 warm window 删除,满了逐出最旧;`nextDelay` 是节奏选择器(45 秒内活跃、45 秒–3 分钟 warm、之后两分钟空闲节奏)。`SupportsMountRemotePolling()` 行为不变(SFTP 仍退出)。已打开但空闲的 Windows 目录按两分钟节奏刷新——Linux(或任何客户端)写入的文件无需重挂即可出现。回归:`remote_poller_test.go`。P0 轮询整体见 [mount_external_sync](mount_external_sync.md)。

## WinFsp 虚拟文件系统引擎

Windows 挂载可在 Cloud Files shell(默认)与 WinFsp 虚拟卷之间选择——后者向 Explorer 报告带用户配置容量的真实卷。WinFsp 引擎编译进每个 Windows CGO 桥接构建(无 build tag);`third_party/winfsp/inc/fuse` 头文件 vendored,经 `CPATH` 由 `run_windows.ps1`、`build_desktop_packages.sh`、`windows/CMakeLists.txt`、`Makefile` `bridge-windows` 指向。仅非 CGO(`CGO_ENABLED=0`)路径用 stub 并报告引擎不可用。

### 关键文件

- `go/mount/backend_windows.go` — `newPlatformMountBackend` 按 `cfg.WindowsMountEngine` 分支:`winfsp` → `newWindowsWinFspBackend`,否则 Cloud Files/WebDAV 模式切换。`cleanupAllManagedMounts` 也调 `cleanupManagedWindowsWinFspArtifacts`。
- `go/mount/backend_windows_winfsp_cgo.go` — `windowsWinFspBackend`(`//go:build windows && cgo`)。`Initialize` 要求盘符并拒绝目录目标(虚拟卷配置只有作为驱动器可靠挂载)。`Start` 容量解析:桶自定义配额 → provider `GetBucketQuota` total/used → 全局 WinFsp 回退。构建 `winFspBucketFS`,goroutine 跑 `fuse.FileSystemHost.Mount`,轮询 `IsActive` 就绪,`-o volname=...` 报卷标 `Cloud Volume <bucket>`。显式 `SectorSize=4096`、`SectorsPerAllocationUnit=1` 匹配 `Statfs`,Explorer 在每个支持的 WinFsp 版本上用同一几何算容量。`Stop` 卸载一次(`stopHost`)、等 serving goroutine、排空写回、释放 bucket access。
- `go/mount/backend_windows_winfsp_stub.go` — `//go:build windows && !cgo`。纯 Go 构建报清晰不可用错误;`cleanupManagedWindowsWinFspArtifacts` 为该路径 no-op。
- `go/mount/winfsp_fs_windows.go` + `winfsp_fs_helpers_windows.go` — cgofuse `FileSystemInterface` 覆盖 `bucketAccess`(Getattr/Readdir/Open/Create/Read/Write/Truncate/Flush/Release/Mkdir/Unlink/Rmdir/Rename/Statfs)。读写复用缓存 + 写回队列。`Statfs` 把解析的 total 与 provider-used 字节报为 total/free 块。helper 文件承载 Stat/错误映射保持两个文件行数内。
- `go/mount/windows_winfsp_probe_windows.go` — `WindowsWinFspAvailable()` 镜像 cgofuse DLL 发现(`winfsp-x64.dll`/`winfsp-a64.dll` 然后 `HKLM\Software\WinFsp\InstallDir`);持有 `hasWinFspMountSuffix`/`isWindowsDriveMount` 供测试与清理无 tag 工作。
- `go/mount/windows_winfsp_embedded_windows.go` — `//go:embed embedded/winfsp.msi` 在桥接内嵌 ~2.1 MB WinFsp 安装器。
- `go/mount/windows_winfsp_install_windows.go` — `InstallWindowsWinFsp` 优先旁挂的 `{app}\winfsp\winfsp.msi`(安装器发布),否则把内嵌 MSI 写临时目录,PowerShell `Start-Process -Verb RunAs -Wait` 提权 `msiexec /i ... /qn /norestart` 后重新探测。提权取消(exit 1223)作为错误浮出供 UI 优雅回退。
- `go/mount/winfsp_backend_windows_test.go` / `winfsp_statfs_windows_test.go` — 盘符校验、路径分类、Explorer-facing Statfs 块单测(无需已装驱动)。
- `bridge/dispatch_mount_winfsp_windows.go` / `dispatch_mount_winfsp_other.go` — 公共分发器在可移植 switch 前委托平台 WinFsp 路由。Windows 注册并实现 `list_windows_winfsp_available`/`install_windows_winfsp`;非 Windows 构建两方法都不处理,解析为标准 unsupported-method 错误而不导入 Windows 挂载符号。
- `lib/services/remote_storage_gateway.dart` — `WindowsWinFspQuery` 接口;`remote_storage_api_desktop_storage.dart` 桌面实现。
- `lib/widgets/windows_settings_sections.dart` — `WindowsMountEngineSection`:引擎下拉(缺驱动时隐藏 WinFsp 选项)、内联说明 + 「安装 WinFsp」按钮、仅 WinFsp 显示容量输入。
- `lib/pages/settings_page.dart` / `settings_page_actions.dart` / `settings_page_sections.dart` — `_winFspAvailable`/`_installingWindowsWinFsp` 状态、依赖变化时探测、安装动作。
- `lib/widgets/mount_bucket_dialog.dart` / `test/mount_bucket_dialog_test.dart` — WinFsp 选择只渲染空闲盘符选择器;Cloud Files 保留路径挂载、WinFsp 隐藏路径,无空闲盘符时禁用提交。
- 构建:`scripts/run_windows.ps1` 设 `CPATH=third_party/winfsp/inc/fuse` 并在头缺失时快速失败;`scripts/build_desktop_packages.sh` `build_windows` 同样导出并校验 `fuse_common.h`;`windows/CMakeLists.txt` 的桥接自定义 target 传 `CPATH`,裸 `flutter build windows` 也能编出引擎;`Makefile` `bridge-windows` 同;`scripts/setup_windows_dev.ps1` `Ensure-WinFsp` 为新机器装驱动;`scripts/windows_installer.iss` / `build_windows_installer.ps1` 把 `winfsp.msi` 发到 `{app}\winfsp` 并加可选「Install WinFsp」安装任务;`third_party/winfsp/inc/{fuse,fuse3,winfsp}` 提交头文件;`go/mount/embedded/winfsp.msi` 内嵌 2.1.25156 载荷。

### Gotchas(binding)

- 桥接分发在每个桌面平台构建。WinFsp case 保持在 `dispatch_mount_winfsp_windows.go`;配对的 `!windows` 文件必须让那些方法名不处理。放进公共 `dispatch.go` switch 或从 `dispatch_mount.go` 调 `WindowsWinFspAvailable`/`InstallWindowsWinFsp` 会弄挂 `go test ./...` 与 macOS `make run`。
- cgofuse 的 cgo 变体(`host_cgo.go`)经 `CPATH` 要求 WinFsp fuse 头(它硬编码 `-I/usr/local/include/winfsp`,只在 xgo/docker 下工作)。头缺失使桥接构建报 `fatal error: 'fuse_common.h' file not found`;构建脚本因此快速失败而不是静默编出无 WinFsp 引擎的桥接。
- WinFsp 是用户态驱动不是内核驱动;内嵌 MSI 是每机器安装并需要 UAC 提权。
- 容量:`Statfs.Blocks * Frsize`;桶 `CustomQuotaBytes` 覆盖 provider 配额,provider 配额覆盖全局 `windowsWinFspCapacityGB`,无 provider 数据用全局回退。`winFspBlockBytes` 固定 4096;`Bfree`/`Bavail` 有 provider-used 时相减,否则镜像 total 块。容量在挂载启动时快照,设置变化需重挂。
- 盘符 WinFsp 挂载(`Z:`)由 WinFsp 自持;`Stop` **不得**对其调 `subst /D`(会失败)。`isWindowsDriveMount` 区分其与 Cloud Files `subst` 映射。
- **不要**为 WinFsp 恢复目录回退:后端把其当契约违反拒绝,对话框必须在挂载命令可用前要求空闲盘符。
