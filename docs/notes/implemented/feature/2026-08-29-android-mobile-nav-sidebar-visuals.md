# Agent Note: 安卓底栏复用桌面侧栏的主题化背景与选中视觉

Status: implemented

## Problem

安卓底栏此前是 Material `NavigationBar`,用 M3 默认 surface 配色:不随应用的强调色(主题设置)变化,与桌面侧栏的品牌渐变、选中胶囊视觉完全脱节——同一应用两端的导航像两个产品。

## Decision

用自绘 `MobileNavigationBar`([lib/widgets/mobile_navigation_bar.dart](../../../../lib/widgets/mobile_navigation_bar.dart))取代 `NavigationBar`:背景渐变、装饰圆形与选中态和桌面侧栏同一套视觉,共享 [lib/theme/sidebar_palette.dart](../../../../lib/theme/sidebar_palette.dart)(bgTop/bgBottom/muted 全部由 `ThemeController` 强调色 lerp 派生)。选中态复刻 `_SidebarNavItem`:强调色前景 + 10% 填充 + 20% 描边胶囊 + w600 文字;未选中为 muted 前景/透明背景,并保留同宽透明描边防止切换时布局跳动(ui_rules 布局不跳规则)。形态适配窄屏:图标上、文字下。`MobileNavItem<T>` 用泛型 value,组件不依赖页面层枚举。`test/mobile_navigation_bar_test.dart` 锁定渐变颜色随强调色派生、选中/未选中文字与胶囊样式、点击回调返回正确 value。

## Alternatives considered

- **用 NavigationBarTheme/M3 seed 把 Material 组件主题化** — 只能换色板,无法复刻侧栏的渐变背景与描边胶囊,等于长期维护第二套视觉体系;胶囊形状与 label 行为还受 M3 约束。
- **只换背景、保留 M3 选中态** — 用户要求两端一致;半套视觉仍是两张皮。
- **直接复用 `_SidebarNavItem`** — 它是横排 icon+文字且依赖 MouseRegion hover,与竖排触控底栏形态不同;两端共享的是调色板与选中视觉参数,不是布局,所以抽出 SidebarPalette 而不是共用条目组件。

## Consequences

- 移动端导航随强调色即时变化;渐变公式只有 SidebarPalette 一个家,桌面侧栏与底栏天然同步演进。
- 底栏维持 5 项固定(文件/账号/回收站/任务/设置);分享管理与文件同步不在移动底栏(移动端本就隐藏同步;分享项保持桌面侧栏专属,与既有移动导航行为一致)。
- 验证:`flutter analyze` 零问题;139 个 widget 测试全过(含新增锁定测试);模拟器上的视觉验收交用户确认。
