# Agent Note: 安卓底栏复用桌面侧栏的主题化背景与选中视觉

Status: implemented

## Problem

安卓底栏此前是 Material `NavigationBar`,用 M3 默认 surface 配色:不随应用的强调色(主题设置)变化,与桌面侧栏的品牌渐变、选中胶囊视觉完全脱节——同一应用两端的导航像两个产品。

## Decision

用自绘 `MobileNavigationBar`([lib/widgets/mobile_navigation_bar.dart](../../../../lib/widgets/mobile_navigation_bar.dart))取代 `NavigationBar`;本版把桌面侧栏的渐变背景、装饰圆形与选中胶囊移植到移动端,并为两端抽出共享调色板 [lib/theme/sidebar_palette.dart](../../../../lib/theme/sidebar_palette.dart)(bgTop/bgBottom/muted 全部由 `ThemeController` 强调色 lerp 派生)。**移动端视觉随后按用户反馈定稿重做**(纯主题背景 + 仅强调色选中,不再用渐变与胶囊),见[定稿笔记](2026-08-29-android-mobile-nav-final-visuals.md);`SidebarPalette` 此后只服务桌面侧栏,该抽取本身仍有效。`MobileNavItem<T>` 用泛型 value,组件不依赖页面层枚举。

## Alternatives considered

- **用 NavigationBarTheme/M3 seed 把 Material 组件主题化** — 只能换色板,无法复刻侧栏的渐变背景与描边胶囊,等于长期维护第二套视觉体系;胶囊形状与 label 行为还受 M3 约束。
- **只换背景、保留 M3 选中态** — 用户要求两端一致;半套视觉仍是两张皮。
- **直接复用 `_SidebarNavItem`** — 它是横排 icon+文字且依赖 MouseRegion hover,与竖排触控底栏形态不同;两端共享的是调色板与选中视觉参数,不是布局,所以抽出 SidebarPalette 而不是共用条目组件。

## Consequences

- 桌面侧栏的渐变公式收口到 SidebarPalette 一个家(自 `main_layout_page.dart` 内联实现迁移,逐值等价)。
- 移动端那部分视觉已被[定稿笔记](2026-08-29-android-mobile-nav-final-visuals.md)取代;底栏维持 5 项固定(文件/账号/回收站/任务/设置),分享管理与文件同步不在移动底栏(移动端本就隐藏同步;分享项保持桌面侧栏专属)。
- 验证:`flutter analyze` 零问题;widget 测试全过;模拟器上的视觉验收交用户确认。
