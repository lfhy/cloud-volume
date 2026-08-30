# App Modal — 统一拟态框与调试子窗口壳

呈现策略的决策背景(为什么应用内模态胜过 OS 子窗口)见 [决策记录](../notes/implemented/architecture/2026-07-11-in-app-modals-over-os-subwindows.md)。

## 统一拟态框(binding)

面向用户的模态 UI 默认**应用内模态**(单 Flutter 引擎)。OS `desktop_multi_window` 编辑器是**仅 debug 的实验特性**。业务代码不得直接调 `showShadDialog`——只有 `lib/services/app_modal.dart` 可以包它。

### 统一 API

- `lib/services/app_modal.dart` — 应用内模态唯一业务入口:
  - `showAppModal` — builder 返回 `ShadDialog` / 双模式编辑器。
  - `showAppModalDialog` — title/description/body/actions 简单表单 helper。
  - `showAppConfirmModal` — 是/否确认(`cancel` + `confirm`,可选 `destructive`)。
  - 常量:`kAppModalDefaultMaxWidth = 480`、`kAppModalDefaultContentWidth = 420`。
  - 唯一允许的 `showShadDialog` 调用点。
- `lib/services/modal_sub_window_debug.dart` — `preferModalSubWindows = kDebugMode && USE_MODAL_SUB_WINDOWS`(默认 false;debug 构建 `--dart-define=USE_MODAL_SUB_WINDOWS=true` 启用)。
- `lib/services/desktop_overlay.dart` — `showDesktopOverlayOrDialog`:gate + 支持时开 debug OS 子窗口,否则应用内模态。**当前唯一生产调用方:** `showRemoteDirectoryPicker`。

### 开启路径路由策略

| 流程 | 默认(release / 常规 debug) | Debug OS 子窗口 |
|------|------------------------------|------------------|
| 账号编辑器 | `CloudStoragePage` → `showAppModal` + `CloudStorageAccountDialog(asDialog: true)` | 仅 `preferModalSubWindows` → `AccountEditorWindowService.openEditor` |
| 同步编辑器 | `file_sync_tasks_page_actions` → `showAppModal` + `FileSyncProfileEditor(asDialog: true)` | 仅 `preferModalSubWindows` → `SyncEditorWindowService.openEditor` |
| 远端目录选择器 | `showRemoteDirectoryPicker` → `showDesktopOverlayOrDialog` → `showAppModal` | 仅 `preferModalSubWindows` → `RemoteDirectoryPickerWindowService.openPicker` |
| 其它对话框 | 总是 `showAppModal` / `showAppConfirmModal` | 无子窗口 |
| 文件预览 | 独立非模态窗口(不变) | 不变 |

桌面窗口服务 `isSupported => preferModalSubWindows`(web 恒 false)。**绝不为「更像原生」而对用户开多窗口模态。**

### 双模式大编辑器(默认 `asDialog: true`;可选 debug OS 子窗口)

| 模态 | 入口/组件 | 打开自 | 备注 |
|-------|-----------|--------|------|
| 账号编辑器 | `CloudStorageAccountDialog` | `account_editor_presenter.dart`(账号管理或文件管理恢复) | 应用内紧凑最大宽 **520**。主表单只保留连接字段;path-style + 代理进嵌套**高级设置**模态(`showAppModal`,最大 **420**)。子窗口内仅内容自适应缩放。 |
| 同步配置编辑器 | `FileSyncProfileEditor` | `file_sync_tasks_page_actions.dart` 增/改 | 舒适最大宽 **600**。三步向导:同步两端 → 同步策略 → 高级设置(排除规则/启用)。嵌套远端选择器。 |
| 远端目录选择器 | `showRemoteDirectoryPicker` / `RemoteDirectoryPickerDialog` | 同步编辑器 step 1、配置备份等 | 舒适最大宽 **640**,体高 **480**。经 `showDesktopOverlayOrDialog`;底部两组动作以 `OverflowBar` + 组内 `Wrap` 按实际宽度自动换行。 |

### 全部应用内模态清单

**文件管理/对象:** 建目录 `CreateDirectoryDialog`;重命名 `showRenameObjectDialog`;复制/移动目标 `showObjectTargetPathDialog`;删除单个 `showDeleteObjectDialog`;批量删除 `showDeleteObjectsDialog`(选择来自 `file_manager_page_selection.dart`);桶设置 `showBucketSettingsDialog`;挂载桶 `showMountBucketDialog`;文件预览 `FilePreviewDialog`(另有独立非模态 OS 预览窗);批量任务进度 `BatchTaskProgressDialog`;面包屑溢出(入口 `lib/widgets/file_manager_breadcrumb_bar.dart`);页面错误/消息 `_showPageMessage`。对话框 helper 在 `lib/widgets/object_action_dialogs.dart`;建目录 `create_directory_dialog.dart`;桶/挂载 `bucket_settings_dialog.dart`、`mount_bucket_dialog.dart`;预览/进度 `file_preview_dialog.dart`、`batch_task_progress_dialog.dart`。

**回收站:** 永久删一条 `showDeleteTrashItemDialog`;批量 `showDeleteTrashItemsDialog`;清空 `showClearTrashDialog`。

**分享:** 时长 `showShareDurationDialog`(小时输入 + 1h–7d 预设);创建成功 `showShareLinkDialog`(复制/打开);详情 `showShareRecordDetailsDialog`;删除单条/批量。全部在 `lib/widgets/share_dialogs.dart`。

**同步/账号/设置/应用 chrome:** 删除同步配置 `showAppConfirmModal`;清理已完成传输(内联);重置全部账号(内联,入口 `lib/widgets/settings_reset_user_config_section.dart`);高级 S3 设置(内联,region + path-style);关闭应用(托盘隐藏 vs 退出);Profile/网关选择器 `ProfilePickerDialog`(暂无活跃调用方,保留备用)。

**非模态:** `FilePreviewWindowApp`(分离非模态预览窗,无 scrim/overlay release);toast(`showAppToast`/`showAppErrorToast`);右键/溢出菜单。

### Gotchas

- 内部有 `Expanded`/固定高列表的大编辑器**不要**外套 `SingleChildScrollView`。优先 `ShadDialog` 内有限高(picker 用 420)或仅在 body 为 `mainAxisSize: min` 时 `scrollable: true`。
- hover/关闭 chrome 遵循全局 hover 规范(`ListInteractionColors`;无水波纹;仅中性洗色,见 [ui_rules](ui_rules.md))。
- Web 恒用应用内模态(窗口服务不支持)。
- 双模式编辑器必须**小于主窗口**:账号/同步 ~600–640、远端选择器 ~640×480。宁可加步骤/嵌套高级模态也不加宽(账号 path-style + 代理在嵌套高级设置;同步排除/启用是 step 3)。
- 简单是/否用 `showAppConfirmModal`;body 有表单/列表/进度时用专门 widget/helper。
- 新增模态:只经 `showAppModal*` 进入,内容保持 500 行内(按 part/feature 拆),并更新本清单。
- `RemoteDirectoryPickerDialog.initial` 只有桶名和 profile 都精确匹配时才恢复目录;空/失效目标停在桶列表,不得把旧 prefix 静默套到首桶。每次目录加载先清旧错误,成功结果必须解除错误态;较旧目录请求的迟到成功/失败都不得覆盖较新导航。回归见 `test/remote_directory_picker_dialog_test.dart`,理由见 [Agent Note](../notes/implemented/bug-fix/2026-08-30-android-backup-directory-picker.md)。
- 选择器的桶、目录、只读文件三类行按**实际列表宽度**局部降级:`<560` 时传 `FileListTile(compact: true)`,把来源/大小等元数据收进标题下方,避免桌面固定元数据列挤压名称;宽屏继续使用标准列。不要按 Android、设备或主窗口宽度判断。

**Known P2/P3 (review 2026-08-30):** P3 桶列表态只有确认动作组时,`OverflowBar` 的 `spaceBetween` 会把它放到左侧;已按动作组数量切换为 `end`,回归同上。

## 桌面模态子窗口壳(通用子窗口壳)

三个**仅 debug** 模态子窗口(账号编辑器、同步编辑器、目录选择器)在 `preferModalSubWindows` 开启时共享同一生命周期:分离 OS 窗口(隐藏标题栏)→ 自绘 44px 标题栏 → bootstrap 桥接/数据 → loading/error/content 体 → 关闭时模态 scrim + overlay release。

### 共享组件

- `lib/widgets/desktop_modal_shell.dart` — `DesktopModalShell`(StatelessWidget):44px 标题栏(标题 + 关闭按钮),取代三个旧的 `_XxxTitleBar`。关闭按钮 hover 遵循 binding(固定 muted X + 中性洗色,无水波纹)。
- `lib/app/desktop_modal_sub_window_app.dart` — `DesktopModalSubWindowApp<T>`(StatelessWidget):通用子窗口根。封装 `ShadApp` + 主题、`_ModalSubWindowLifecycle`(dispose/close 时 overlay release)、`DesktopModalParentFocusRelay`(可选 `useParentFocusRelay`)、`DesktopModalWindowFocusGate`、`DesktopModalScrim`、`DesktopModalShell`、bootstrap 驱动的 loading/error/content 体。特性提供 `bootstrap: Future<T> Function()` 与 `contentBuilder: Widget Function(BuildContext, T, Future<void> Function() close)`。第三个 `close` 参数是公共关闭序列 `closeDesktopModalSubWindow(...)`(可选 `onClose` → 注销子窗 → 通知创建者 overlay release → 清 chrome → `windowManager.close()`)。**`scrollable`(默认 true):** true 时 body 是 `Padding` + `SingleChildScrollView`(表单类内容如账号编辑器);false 时只有 `Padding`,内容从 shell `Expanded` 获得有限高——供用 `Expanded`/fill-height 列表的 widget(`FileSyncProfileEditor`、`RemoteDirectoryPickerDialog`)。**绝不**给 fill-height 编辑器套外层滚动。
- `lib/app/desktop_modal_window_config.dart` — `configureDesktopModalSubWindow()`:统一 `WindowOptions` + `waitUntilReadyToShow` + `applyModalChildWindowChrome` + `setTitle` + `show` + `positionChildCenteredFromFrame` + `focus`,取代各窗口 `_configure*Window`。
- `lib/widgets/measure_size.dart` — `MeasureSize` RenderObject 上报子尺寸变化(含仅后代重建,如代理自定义字段)。
- `lib/services/desktop_sub_window_modal.dart` — `fitModalSubWindowToContentSize` 把测量体尺寸 + 标题栏(44)+ 内容 padding 转为居中 OS 窗口尺寸,只钳固定 min/max(绝不用 `FlutterView.physicalSize`——多窗口下那是子窗口自身)。
- `lib/services/desktop_modal_overlay_controller.dart` / `lib/widgets/desktop_modal_scrim.dart` — debug 子窗口路径的父级 scrim 与 overlay 释放控制;`lib/services/desktop_window_method_host.dart` — 子窗口结果/overlay/边界的 method 复用宿主。
- `lib/app/app_entry_io.dart` — 三个模态窗口都经 `configureDesktopModalSubWindow()` 配置;`_configurePreviewWindow` 保留(非模态、居中、无 chrome)。

### 迁移后的窗口与初始尺寸

- 账号编辑器:`DesktopModalSubWindowApp<RemoteStorageGateway>` + `scrollable: true`(内容超屏幕钳制时的溢出保护);bootstrap → `defaultRemoteStorageApiFactory()`;`onSaved` 通知父级再 `close()`。内容自适应缩放在 `CloudStorageAccountDialog`(`MeasureSize` + `fitModalSubWindowToContentSize`)。初始种子尺寸/编辑模式尺寸见 [account_management](account_management.md) 窗口尺寸策略。
- 同步编辑器:`DesktopModalSubWindowApp<_SyncBootstrapResult>` + **`scrollable: false`**(编辑器自持步骤指示 + 内部滚动 + `Expanded` 固定导航);固定初始 `600×480`,步骤尺寸 600×480/500/480。
- 远端目录选择器:`DesktopModalSubWindowApp<RemoteStorageGateway>` + **`scrollable: false`** + `useParentFocusRelay: false`(`lib/app/remote_directory_picker_window_app.dart`;args `lib/models/remote_directory_picker_window_args.dart`;服务 `lib/services/remote_directory_picker_window_service.dart`);args JSON 同时携带真实桶 identity、`displayName` 与 `rootPrefix`,展示别名和限定根目录不得跨 debug 子窗口丢失;`onConfirm` 暂存结果再 `close()`;标题栏 X 走 shell `onClose` → `_sendResult`(无选择则 null)。固定 `640×560`(min 480×400)。
- 未迁移:`FilePreviewWindowApp` — 非模态独立窗口(无 scrim、无 overlay release、可拖标题栏),模式根本不同,保持独立。
- 近 500 行的双模式内容组件:`cloud_storage_account_dialog.dart`(~471)、`file_sync_profile_editor.dart`(~480)、`remote_directory_picker_dialog.dart`(~446);shell/服务远低于 500(除 `desktop_sub_window_modal.dart` ~355)。

### Gotchas(binding)

- 内容用了 `Expanded`、`height: double.infinity` 或内部滚动区(`FileSyncProfileEditor._buildSubWindowLayout`、`RemoteDirectoryPickerDialog`)时**绝不**设 `scrollable: true`——外层 `SingleChildScrollView` 使高度无界,`RenderFlex children have non-zero flex but incoming height constraints are unbounded` 崩溃。
- 内容必须在保存/取消/确认路径调用注入的 `close`。标题栏 X 已走 shell `onClose` → `closeDesktopModalSubWindow`;空 `onCancel`/`onSaved` 回调会让窗口在迁移后保持打开。
- 子窗口内**不要**嵌套 `ShadDialog`(`asDialog: false`)。文件预览不属于本壳——不要动它。
- 账号编辑器用**内容测量**缩放(`MeasureSize` + `fitModalSubWindowToContentSize`),不是手调每步高度;只有收缩包裹(`MainAxisSize.min`)的表单内容可用。同步编辑器/目录选择器保持离散/填充高布局,**不得**调内容自适应。
- 内容自适应必须加 shell chrome:标题栏 44px + 内容 padding `LTRB(24,16,24,24)`(+ 小高度余量)。只测表单体并当作 OS 窗口尺寸会切掉 chrome 或重新引入滚动/留白。
- `MeasureSize` 必须上报**子项无约束高度**(`maxHeight: infinity` 布局),不是父 `Expanded`/种子窗口强加的短尺寸——上报钳制后尺寸会欠测并切掉按钮行。
- 内容自适应缩放后用窗口 args 里的创建者 frame 经 `positionChildCenteredFromFrame` 重新居中。不要只在首次显示调 `resizeKeepingWindowCenter`——子窗可能仍在默认 OS 原点并跳变/偏离中心。
- **绝不**在多窗口子引擎内用 `FlutterView.physicalSize`/`platformDispatcher.views.first` 钳内容自适应——那报告的是**当前子窗口**,`max = size * 0.9` 会让每次 next/back 缩小对话框。用固定 `maxSize`(或来自主进程的真实显示器 API)。
