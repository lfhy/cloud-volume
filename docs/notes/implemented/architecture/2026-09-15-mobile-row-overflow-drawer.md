# Agent Note: Android 行级 `…` 抽屉模型（取代选中动作条）

Status: implemented

## Problem

[选中动作条批次](2026-09-15-mobile-selection-action-bar.md)落地后用户提出三点修正:(1) 去掉「全选」;(2) 两页布局仍与文件管理页不一致——文件管理页的搜索框与列表紧贴,任务/回收站页在筛选区与列表间还有列表头与 16dp 间距;(3) 所有可用动作应收进**每一行尾部 `…`** 的底部抽屉,像文件管理页那样,而不是选中后弹底部动作条。

## Decision

1. **行级 `…` 抽屉(文件管理契约)**:Android 上每行尾部一个 48dp `ellipsisVertical` 入口打开 `showMobileActionSheet`——无选中/单个选中时为该行动作;本行已选中且选中数 >1 时为当前选择的批量动作(含「取消选择」,抽屉标题「已选 N 个 X」)——触发条件与文件管理对象行完全一致(评审纠正了初版「任意选中即批量」的偏差,单个选中的批量等价于行自身动作)。回收站行:恢复/彻底删除 → 批量 恢复 N 项/彻底删除 N 项(`GlobalTrashBrowser` 新增 `onBatchRestore`/`onBatchDelete`/`batchSelectedCount` 参数);任务行:立即执行/取消任务/重试/清理历史 → 批量同名动作(`RemoteTaskOverflow` 载荷由 `transfers_page_remote_overflow.dart` part 文件装配,`RemoteTaskRow.mobileOverflow` 构建器注入)。行内保留状态徽标、活动 spinner 与明细展开;桌面保持内联图标。
2. **删除选中动作条与全选**:`MobileSelectionActionBar` 组件删除;两页 Android 不再有全选入口——任务页列表头(共 N 项/全选/速度汇总)与回收站 compact「全选」头一并移除(桌面保留各自表头)。
3. **布局对齐文件管理页**:头部后 16→14dp、筛选/搜索后 16→12dp,列表上缘紧贴搜索框;两页一致。
4. **页面级入口常驻**:任务页(立即同步/清理全部历史)与回收站页(刷新/清空)右上角单一入口在选中态不再隐藏——与文件管理页 `+` 入口行为一致;批处理运行中入口变 spinner、行抽屉动作集为空。

## Alternatives considered

- **保留选中动作条、仅去掉全选** — 用户明确要求动作进行级抽屉(文件管理契约),且条与行抽屉并存会两套批量入口。
- **批量动作放页面入口抽屉** — 页面级(立即同步/清空)与批量(作用于所选)语义不同;文件管理页正是「行抽屉承载行级+批量、页面入口承载页面级」的分工。
- **保留全选于行抽屉/长按** — 用户点名去掉;桌面表头全选保留不受影响。
- **保留列表头只去全选** — 仍与文件管理页(搜索框下紧贴列表)不一致,「共 N 项/速度」在 Android 一并放弃(桌面与 macOS 用例继续覆盖)。

## Consequences

- Android 任务页损失「共 N 项/速度汇总」常显信息(文件管理页同样无此类头部);分页行 `_RemoteHistoryPager` 仍在列表尾部承载计数提示。清空选择的唯一入口是批量抽屉的「取消选择」(文件管理同款);未进入批量态时可逐行点击取消。
- `transfers_page_remote.dart` 因新增装配逻辑拆出 `transfers_page_remote_overflow.dart` part 文件(执行了 remote_tasks 正典既有的拆分预告)。
- 每行 `…` 都能触发批量动作(与文件管理对象行一致);批处理运行中所有行抽屉空置、页面入口显 spinner。
- 选中动作条组件及其测试删除;「共 N 项」断言的队列用例钉到 macOS(该表面现为桌面专属)。
- 桌面(含窄窗)渲染不变:表头、全选、内联图标、卡片均保留。

## Verification

- `flutter analyze` 干净(仅 2 条既有 deprecation info);`flutter test` 全量通过。
- widget_test「Android dedicated trash tab」钉住:行 `…` 无选中=恢复/彻底删除,选中行后=批量(已选 1 个文件/恢复 1 项/彻底删除 1 项),页面入口全程可见;transfers「android row overflow owns selection actions」钉住单行↔批量切换与入口常驻;「selected history uses explicit cleanup」改经行抽屉驱动;「small history queues render their complete count」钉 macOS 表面。
