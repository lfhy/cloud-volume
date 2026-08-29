# Agent Note: 安卓底栏视觉定稿——纯主题背景与强调色选中

Status: implemented

## Problem

第一版把桌面侧栏的渐变背景、装饰圆形与选中胶囊整体移植到安卓底栏(见[前一版笔记](2026-08-29-android-mobile-nav-sidebar-visuals.md));用户看后认为不如原来好看,并给出参考截图定稿:底栏干净无背景装饰,选中后只是图标+文字变主题色。需要在"两端视觉一致"与移动端观感之间重新定稿。

## Decision

底栏最终视觉([lib/widgets/mobile_navigation_bar.dart](../../../../lib/widgets/mobile_navigation_bar.dart)):纯 `ShadTheme.colorScheme.background` 铺满到屏幕物理底部(无渐变、无装饰圆、无选中底块),顶部一条全量 `colorScheme.border` 线提供与内容区的分割感(用户先反馈纯同色缺分割感,再反馈 70% 透明档不够明显;参考图解析定档为白底约 8% 黑,浅色主题的全量 border ≈8.8% 黑、同档略强于参考,复审确认不刺眼),图标上文字下(icon 24 / 文字 12);选中态 = `ThemeController` 强调色图标+文字 + w600,未选中 = `colorScheme.mutedForeground` + w500;无胶囊/描边/指示器。`SidebarPalette` 继续只服务桌面侧栏,移动端不再引用它——两端共享的只剩强调色来源。`test/mobile_navigation_bar_test.dart` 重写为锁定:所有 BoxDecoration 无渐变、顶部分割线、选中图标/文字为强调色、未选中为 mutedForeground、点击回调返回正确 value。

## Alternatives considered

- **保留侧栏渐变 + 胶囊(第一版)** — 用户明确否定:窄屏上一整条渐变底栏视觉过重、与内容区抢焦点;参考设计更轻更现代。
- **选中项加浅色胶囊(强调色 8–10% 填充)** — 对参考截图的视觉解析与用户确认都表明没有选中底块("没有浅色底块,就是选中后图标+文字变成主题色");不再引入第二套选中语言。
- **底栏纯透明(不设背景色)** — 页面内容滚动会从底栏下方穿透;参考图是不透明底。用 `colorScheme.background` 等价呈现且天然遵循主题。

## Consequences

- 移动底栏与桌面侧栏的视觉解耦:共享的契约只有"强调色来自 ThemeController";桌面渐变公式仍在 SidebarPalette 一个家,不因移动端改版而动。
- 无胶囊后不再有描边宽度/布局跳动问题;Semantics 保留 `button`/`selected`(不带 label,由 Text 自报避免 TalkBack 连读)。
- 验证:`flutter analyze` 零问题;139 个测试全过(锁定测试重写);模拟器视觉验收交用户。
