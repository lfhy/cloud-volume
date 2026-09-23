# Agent Note: Android 头部动作收进单一入口 + 底部抽屉

Status: implemented

## Problem

无边框批次之后,五个底栏页里仍有两页把可选动作直接内联暴露在头部右侧:任务队列页常驻「立即同步 N」「清理全部历史 N」按钮、选中后换「清理历史 N」;全局回收站页把桌面风格的 `GlobalTrashHeaderActions` 按钮组(刷新/清空/批量恢复/批量彻底删除 + 已选 chip)原样搬进手机头部。文件管理页的既定模式是:右上角一个带语义的 48dp 图标入口,点开底部动作抽屉,没有可用动作时入口隐藏(mobile_ui.md 既有 binding)。两页的头部按钮密度与该基线冲突,也是 2026-09-04 批次评审时记录过的宽度风险来源。

## Decision

任务页与回收站页的 Android 头部改为「单一 48dp 入口 + `showMobileActionSheet` 底部抽屉」,入口用 `ellipsisVertical` 图标 + `Semantics`(任务操作/回收站操作),复用 `mobile_page_chrome.dart` 的共享实现:

- 任务页抽屉动作集:未选中时「立即同步 N」(syncable>0)与「清理全部历史 N」(historyTotal>0);选中时仅「清理历史 N」(clearable>0)。批处理运行中(`_runningBatchAction`)入口图标换成页面主体档 `AppLoadingIndicator`(22/2.4,ui_rules 既有分档)保留可见进度,动作列表为空(含运行中)时入口整体隐藏。
- 回收站页抽屉动作集:未选中「刷新」+「清空回收站」(有活动桶且有条目);选中「批量恢复」「批量彻底删除」。批量动作按**过滤后仍可见的选中数**门控(与桌面 `GlobalTrashHeaderActions` 一致),搜索把所选条目全部排除时回到未选中动作集。Android 头部不再渲染 `GlobalTrashHeaderActions`,「已选 N 项」继续由标题槽承载(原有 chip 冗余,随按钮组一起移除)。
- 忙碌反馈从「按钮内 spinner + 正在…文案」改为「入口图标变 spinner」;桌面路径的内联按钮、间距、loading 文案逐字不变(`_queueActionButton` 的 48dp 包装分支随 Android 内联按钮一起删除)。

## Alternatives considered

- **把任务页/回收站页头部迁移到 `MobilePageHeader`** — 两页都有选中态标题互换(标题槽换「已选 N 项」)与运行中 spinner,`MobilePageHeader` 不支持;为其加参数会让共享组件承载单页状态,不如页内自持入口。
- **保留「立即同步」为内联主按钮,只收次要动作** — 仍是两套头部密度,且选中态切换会把入口位置挤动;单一入口的位置稳定优先。
- **忙碌时禁用入口而非变 spinner** — 清理大 journal 历史可达数秒,无可见反馈会被当成无响应;入口 spinner 是 100ms 内可见的最小反馈。
- **回收站页保留「已选 N 项」chip** — Android 标题槽已承载同一信息,chip 与按钮组同属桌面遗留,一起收掉。

## Consequences

- Android 任务页头部按钮宽度风险(2026-09-04 批次 P2 记录的 343px 最坏组合)消除:头部只剩标题 + 单一 48dp 入口。
- 抽屉动作点击即关抽屉再执行动作;进行中状态只能从入口 spinner 观察,按钮内「正在同步…」等文字反馈在 Android 不再存在(桌面保留,desktop inline loading label 用例钉住)。
- `GlobalTrashHeaderActions` 变为桌面专属组件,Android 分支不再引用。
- 回收站页加载中(列表主体是 spinner)抽屉无可用动作,入口隐藏;刷新只能等加载结束——与旧按钮「加载中禁用」等价。
- 条目/批量 mutation(`_restoreEntry`/`_deleteEntry`/`_restoreSelected`/`_deleteSelected`/`_clearActiveBucketTrash`/`_runBusy`/`_showPageSnack`)拆到 part 文件 `global_trash_page_actions.dart`,主文件回到 500 行以内。
- 回归:transfers 批量用例改经抽屉驱动(门控 spinner 持续动画,须用有界 pump 而非 pumpAndSettle);widget_test 两处断言空队列入口隐藏与回收站抽屉打开。

## Verification

- `flutter analyze` 干净(仅 2 条既有 deprecation info);`flutter test` 全量通过(含改写的 4 个 transfers 批量用例、新「android queue actions collapse into the header sheet」用例、desktop inline loading label 用例与 widget_test 任务/回收站页断言)。
- 桌面零回归:提交前评审对桌面按钮顺序/间距/enabled 条件/loading 文案做了 HEAD 逐项 diff 比对(重构进 `!_androidCompactQueueHeader` 分支、删除 `_queueActionButton` 包装后语义等价),既有 macOS 用例(batch cancel from header)与 `global_trash_header_actions_test.dart` 通过。
