# UI Rules — Flutter 前端组织与视觉规范(binding)

Flutter 代码按类型优先、再按特性组织:`lib/app`、`lib/pages`、`lib/widgets`、`lib/services`、`lib/state`、`lib/utils`、`lib/theme`、`lib/bridge`、`lib/models`。入口文件保持薄——只做模块装配,不内联页面逻辑;大 widget 树拆进 page/widget 模块,而不是一个超大的 `build()`。bootstrap/配置流程与存储浏览器在视觉上保持区分,首启行为一目了然。

## Hover 可点击行(binding 规则)

任何需要 hover 视觉响应的可点击行、卡片、tile、侧边栏项,**必须是独立的 `StatefulWidget`**,自带 `bool _hovered` 字段。该字段由 `MouseRegion(onEnter/onExit)` 写入并触发 `setState`,通过 `AnimatedContainer` 驱动背景色(仅在有意为之 时也驱动文字/图标色)。这是让 hover 重建子树的唯一可靠方式。

**绝不**把 hover 项写成 extension on State 或普通 builder 里的内联 `MouseRegion + Container`——extension/builder 没有可变字段存放 `_hovered`,`onEnter/onExit` 无处可写,hover 永不重建,得到死掉或卡住的 hover 状态。此 bug 已多次复发(设置侧栏、文件列表 tile)。

### Hover 视觉样式(硬性产品规则——每次碰 hover UI 前必读)

Hover 是**轻微的状态变化**,不是换一套组件皮肤。硬规则:指针划过一排卡片/按钮时,hover 项不能看起来像换了设计。

**hover 时只允许:**
- 通过 `ListInteractionColors.fromTheme` 做背景洗色(`hover` = 中性 `mutedForeground @ ~0.08`)
- 已**选中**项可再加深一档

**hover 时禁止(除非该项的常驻状态就是选中/禁用):**
- 改**图标颜色**(muted → primary、灰 → 红等)
- 改**边框颜色**或**边框宽度**
- 改**字重/文字颜色**
- 换另一套填充体系(`colorScheme.secondary` 蓝、destructive 粉红填充等)
- 显示/隐藏引起布局重排的尾部元素(对勾)

**发布任何 hover 控件前的检查清单:**
1. idle 与 hover 截图应只差一层浅背景,不是「换主题」。
2. idle 与 hover 的图标/边框/文字完全一致(同 Color/宽度/字重)。
3. 用 `ListInteractionColors.rowBackground(selected:, hovered:, pressed:)`,**不要**自创 per-feature 调色板。
4. 独立 `StatefulWidget` + `_hovered` + `MouseRegion` + `GestureDetector(behavior: opaque)` + `AnimatedContainer`。
5. 布局不跳(固定边框宽度;预留对勾宽度;不许 1→1.5 边框)。
6. 标题栏/chrome 按钮(含模态框关闭):**无 Material 水波纹**;hover = 中性洗色;**不得**把 X 变红/变粉。

**反面教材(已修复的回归,不得复现):**
- 协议卡片:hover → primary 边框 + `secondary` 填充 + primary 图标(`StorageProtocolCard`)。
- 模态框关闭按钮:hover → 粉红填充 + 红 X。正确做法 = 固定 muted X + 仅中性洗色。

**可参考的正典实现:**
- `lib/theme/list_interaction_colors.dart` — 共享 hover/selected 洗色。
- `lib/widgets/desktop_sidebar.dart` `_SidebarNavItem` — 侧栏导航项。
- `lib/widgets/file_list_tile.dart` — 文件管理行(`dimmed` 禁用 hover)。
- `lib/widgets/transfer_task_widgets.dart` — 传输队列行。
- `lib/pages/settings_page_layout.dart` `_SettingsGroupTile` — 设置左栏条目。
- `lib/widgets/cloud_storage_account_dialog_steps.dart` `StorageProtocolCard` — 可选卡片(中性 hover;primary 视觉仅选中时出现)。
- `lib/widgets/desktop_modal_shell.dart` `_ModalShellCloseButton` — 模态标题栏关闭(无水波纹;仅中性 hover)。

光标:密集列表行 idle 用 `SystemMouseCursors.basic`,仅 hover 时切 `click`(常驻可交互卡片可用恒定 `click`);绝不许 unhover/unmount 后残留手型光标。

## Loading 指示器(binding — 以文件管理页为基准)

所有 loading spinner 必须用 `AppLoadingIndicator`(`lib/widgets/app_loading_indicator.dart`,shadcn 风格弧形 + 18% 透明度轨道)。`lib/` 下**禁止**出现原生 `CircularProgressIndicator`(头部样式不同、无轨道、默认 4px 描边破坏视觉节奏)。

尺寸分档(文件管理页是基准;照抄,不要重新发明):

| 场景 | 规格 | 参考实现 |
|---|---|---|
| 页面主体加载 | `Center > Column(min) > AppLoadingIndicator(size: 22, strokeWidth: 2.4)` + 12px 间距 + 阶段文案(`textTheme.p` w600)+ 可选 muted 13px detail | `lib/pages/file_manager_page.dart` `_buildLoadingView`、任务队列 `_RemoteInitialLoading` |
| 按钮/动作内联 | `AppLoadingIndicator(size: 14, strokeWidth: 2)` + 7px 间距 + 动作词;实心按钮传 `color: primaryForeground` | `lib/pages/login_page.dart`、`transfers_page.dart` `_batchActionButtonChild` |
| 对话框主体 | `AppLoadingIndicator()`(默认 18/2)居中,保留原有固定高度/内边距 | `bucket_visibility_dialog.dart`、`remote_directory_picker_dialog.dart` |
| 密集行内 | 12–15px,strokeWidth 1.5–2,跟随语境配色 | `remote_task_widgets.dart` 任务行 spinner(12/1.6 primary) |
| 大对话框 hero | `AppLoadingIndicator(size: 42, strokeWidth: 3)` | `lib/widgets/file_preview_dialog.dart` |

- `LinearProgressIndicator` 只允许用于**进度条**——有确定进度(批量任务、下载、配额),或总量未知但确属进度场景(更新安装 `value: null`);不得作为通用 loading spinner。
- 纯文字 busy 文案(「统计中...」「处理中...」)保持纯文字;周围 chrome 已表达状态时不要再加 spinner。
- 页面主体 loading 必须带阶段文案(「正在加载任务…」「加载存储桶...」);对话框主体在触发按钮已说明动作时可省略文字。

## 设置卡视觉一致性

每个 `Settings*Section` 遵循同一结构:顶部 12px muted 简介文字,然后 secondary-container 块(`colorScheme.secondary`,圆角 10,内边距 14/12),功能组之间可放 `_SectionHeader`(14px w700 标题 + 11.5px muted 描述)。设置卡内**不用** `textTheme.h4`(它是页面级标题专用)。正典卡布局见 `lib/widgets/settings_p2p_section.dart`。
