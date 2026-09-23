# Agent Note: Android 选中态底部动作条（取代标题槽切换）

Status: implemented

## Problem

[2026-09-15 头部动作抽屉批次](2026-09-15-mobile-header-action-sheet.md)把选中态批量动作放进右上角抽屉、把标题槽换成「已选 N 项」。用户反馈要求改为更直接的选中交互:选中列表条目后弹出一个底部动作条——顶行 左「取消」/ 中「已选中 N 个文件」/ 右「全选」,下方一行「恢复」「删除」等批量动作;任务队列同理。抽屉式选中动作要多一次点击才能到达,且计数在标题槽、动作在抽屉,视线来回跳。

调查中还发现一个让该交互在回收站页走不通的存量 bug(此前测试从未驱动过移动端回收站行选中,一直未暴露):行上非空 `onDoubleTap`(桌面双击恢复)使单/双击识别器并存,行单击的选中被嵌套 tap 双触发立即取消,净效果为零。评审澄清了机制归因:右键菜单包装(`DesktopContextMenuRegion`)并不吞点击——对象移动行用同样的包装且点击正常,故行继续保留该包装(桌面与 Android 长按菜单都可用),唯一需要的修复是 `onDoubleTap` 置空。

## Decision

1. **共享组件** `MobileSelectionActionBar`(`lib/widgets/mobile_selection_action_bar.dart`):顶行 48dp「取消」(清空选择)/居中「已选中 N 个 X」/「全选」(复用各页现有 select-all 切换),发丝分隔线下方一行批量动作按钮(图标+标签,破坏性动作 destructive 色,批处理运行中禁用为 muted,48dp)。平铺无边框,底部避让 `MediaQuery` 安全区;页内以 `AnimatedSize`(200ms)包在列表下方,选中集非空出现、清空收起。
2. **任务队列**:动作条为 立即执行(triggerable>0)/取消任务(cancelable>0)/清理历史(clearable>0,destructive),运行中禁用;「取消任务」刻意区别于顶行「取消」。标题槽恢复常显「任务队列 + 副标题」,不再切换;右上角抽屉只承载未选中态动作(立即同步/清理全部历史),选中态整体隐藏(运行中入口仍以 spinner 显现提示进度)。动作条按「过滤后仍可见的选中」门控并计数,搜索排除全部所选时条隐藏,与回收站一致。
3. **回收站**:动作条为 恢复/彻底删除(destructive),按 `selectedFilteredCount>0` 门控;桌面 chip 与标题槽切换一并移除,标题常显;抽屉同样只留未选中态(刷新/清空回收站)。
4. **行点击修复**:`GlobalTrashBrowser` 行的 `onDoubleTap` 在 Android 置空(双击恢复是桌面 affordance,移动端恢复走行尾图标与动作条);右键/长按菜单包装保留不变。

## Alternatives considered

- **沿用「标题槽换已选 N + 动作进抽屉」** — 被用户明确否决:动作多一跳、计数与动作分离。
- **动作条做成悬浮/圆角 overlay 贴底** — 引入第三种容器风格(非平铺、非模态);嵌在页面 Column 里 + 发丝顶线与无边框基线一致,且天然随 SafeArea/底栏排布。
- **顶部 contextual app bar(Android 传统模式)替换整个头部** — 改动面大且与共享 `MobilePageHeader` chrome 冲突;底部条保留稳定标题,信息层级更简单。
- **全选放成三态勾选框** — 顶行已是文字按钮布局,复用各页 `_toggleSelectAll*`(本身即切换语义)足够;不引入新控件。
- **只修行点击、不动动作条** — 用户要的正是动作条;两个修复相辅相成(行选中是动作条的前置)。

## Consequences

> 2026-09-15 晚些时候,本条的选中动作条模型按用户反馈被 [行级 `…` 抽屉模型](2026-09-15-mobile-row-overflow-drawer.md) 取代:`MobileSelectionActionBar` 组件已删除,批量动作移入行尾抽屉;本条中的行点击修复(`onDoubleTap` 置空)与标题常显决策继续有效。

- 选中态交互:点行/勾选 → 底部弹条(计数+全选+取消+批量动作);批量动作一键直达,不再经过抽屉。
- 标题槽在选中态不再变化(两页常显标题+副标题);「已选 N 项」标题切换文案从这两页消失,其他组件(文件页对象操作表、桌面 chip)不受影响。
- 批处理运行中(清理历史等)时右上角入口仍以 spinner 出现提示进度——选中态运行动作时入口专为 spinner 显现。
- 回收站桌面双击恢复保留;移动端双击不再有语义(单击即选中),行右键/长按菜单不受影响。
- Android 全局回收站行点击自 2026-09-04 以来实际不可用(onDoubleTap 双触发),本批修复并由 widget_test 钉住。

## Verification

- `flutter analyze` 干净(仅 2 条既有 deprecation info);`flutter test` 全量通过。
- 新增/改写用例:widget_test「Android dedicated trash tab」钉住行点击选中 → 动作条(计数/恢复/彻底删除/入口隐藏)→ 条上取消收起;transfers「android selection bar keeps the title and owns batch actions」钉住标题常显、动作条出现、入口隐藏、条上取消清空;「selected history uses explicit cleanup」改经动作条驱动;桌面用例(macOS 内联按钮、desktop loading label)不受影响。
