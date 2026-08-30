# Agent Note: 业务模态统一应用内拟态框,OS 子窗口降为 debug 实验

Status: implemented

## Problem

账号编辑器、同步配置编辑器、远端目录选择器三个大编辑器曾以 OS 分离窗口(`desktop_multi_window`)为主路径。每个窗口各自重复实现标题栏、关闭序列、`WindowLifecycle` overlay 释放、bootstrap、焦点与 scrim(三个标题栏 widget ×3、关闭函数 ×3、`_configure*Window` ×4);多 Flutter 引擎带来调试与生命周期成本,Web 平台根本不可用,平台差异(焦点 relay、居中、尺寸钳制)逐一踩坑。

## Decision

面向用户的模态默认走**单引擎应用内模态**:

- `lib/services/app_modal.dart` 是唯一业务入口(`showAppModal` / `showAppModalDialog` / `showAppConfirmModal`),全仓库唯一允许的 `showShadDialog` 调用点;业务代码不得直接调 `showShadDialog`。
- 业务 surface 统一构造 `AppShadDialog`:Android 使用键盘后可用约束全屏、背景延伸到系统栏且内容留在 SafeArea,桌面/Web 仍透传有限宽 `ShadDialog` 行为。系统栏样式由 route 内 `AnnotatedRegion` 管理,不写泄漏到下一页的命令式 `SystemChrome` 状态。
- OS 子窗口降级为 `preferModalSubWindows = kDebugMode && USE_MODAL_SUB_WINDOWS`(默认关)的 debug 实验路径,三个窗口共享 `DesktopModalSubWindowApp` 壳(标题栏/生命周期/scrim/内容自适应缩放),不再各自为政。
- 桌面/Web 双模式编辑器(`asDialog`)保持小于主窗口(账号/同步约 600–640、选择器 640×480),宁可加步骤/嵌套高级模态也不加宽;Android 为全屏例外,fill-height 编辑器常规高度下自持中段滚动与固定动作区,低可用高度下移除无界 flex,让 Shad 把标题、说明、主体与动作置于同一滚动面以保持聚焦与动作可达。

现行清单与路由表见 [app_modal](../../../features/app_modal.md)。

## Alternatives considered

- **全面原生多窗口(更"桌面原生"的观感)** — 每窗口 bootstrap 桥接、焦点管理、scrim/overlay 释放、结果回传的持续成本,换来 Web 不一致、调试翻倍;观感收益撑不起工程成本。
- **全部退化为页面内联编辑(不用模态)** — 大表单需要模态焦点与阻断上下文,内联会让长编辑状态与列表状态互相干扰。
- **只在 route 外包 `SizedBox.expand` 或覆盖 `ShadDialogTheme.constraints`** — 上游根节点 `Align` 会放松子约束,且账号/选择器显式 constraints 优先于 theme,白色 surface 仍是居中截断矩形;因此选择完整转发属性的 `AppShadDialog` 适配器。

## Consequences

- 模态呈现单一可审计入口;Web 与桌面行为天然一致;hover/关闭 chrome 规则只需在一个体系里执行。
- Android 不再露出上下 barrier 暗带;状态栏/导航栏图标随主题可见,软键盘只压缩可用 surface。代价是全屏没有可点击的“模态外侧”,取消依赖关闭按钮或系统返回,而 `Navigator.pop(result)` 契约不变。
- 代价:debug 子窗口壳仍需维护(内容测量 `MeasureSize` + `fitModalSubWindowToContentSize` 的 chrome 补偿、多窗口内禁用 `FlutterView.physicalSize` 钳制等 gotcha),但范围收敛到一条实验路径。
- 历史修复(2026-07-11 同日 `StorageProtocolCard` 与模态关闭按钮 hover 回归)与呈现策略切换的过程记录在 [PROJECT_GUIDE](../../../PROJECT_GUIDE.md);`docs/features/app_modal.md` 持有现状清单。
