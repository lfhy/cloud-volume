# Agent Note: 移动端可配置底栏与首页、返回键历史栈

Status: implemented

## Problem

移动端底栏此前是硬编码五项(文件·账号·回收站·任务·设置),回收站落在中间位置观感奇怪;没有首页概念;安卓返回键直接退出应用而不是回到上一个页面。用户先提出"首页放中间、回收站后移",随后升级为更通用的诉求:底栏显示哪些页面、按什么顺序,应该让用户自己在设置里配置(且该配置是移动端专属)。

## Decision

- **配置驱动底栏**:`lib/state/mobile_nav_preferences.dart` 把可见项+顺序持久化到 SharedPreferences(`mobile.bottom_bar_items`),默认 `文件·账号·首页·任务·回收站`;可选池 `kMobileBottomBarPool` = home/fileManager/storage/transfers/trash/settings。约束:**2–5 项,且 home 与 settings 至少保留其一**——两者都不在底栏时设置页将失去全部入口,这是防死锁的硬约束;解析损坏/非法数据回退默认。main_layout 以 `ListenableBuilder` 监听,设置里改动即时重建底栏。
- **设置节(移动端专属)**:`SettingsMobileNavSection` 挂在设置页常规组,`_railGroups` 里用平台条件(**仅 Android 渲染**)。UI 为每项开关 + 上移/下移 + 恢复默认(触控场景不用拖拽排序);约束失败 toast 提示且不动状态。
- **首页**:`MobileHomePage`(SidebarItem.home,IndexedStack 索引 7):问候 + 账号概览、任务状态卡、快捷入口 2×2(文件/账号/回收站/**设置**)、最近任务前 3 条;数据全部复用 `RemoteTaskStore` 与 `BootstrapState`,首页不发起新请求。桌面侧栏不显示 home。
- **返回键历史栈**:`lib/state/tab_nav_history.dart` 纯逻辑类(visit 去重 / back 跳过不可见项 / 耗尽返回 null),main_layout 在 Android 上用 `PopScope(canPop: !canGoBack)` 拦截系统返回:回退到上一个仍在底栏配置中的 tab,历史耗尽才允许退出。
- **结构**:`SidebarItem` 枚举迁到 `lib/models/sidebar_item.dart`(配置/首页/设置节/两个布局共用,附带 icon 与 desktopLabel/mobileLabel extension);桌面侧栏从 main_layout 拆出 `lib/widgets/desktop_sidebar.dart`(行为不变,主装配文件回到 500 行内)。

## Alternatives considered

- **固定顺序(首页硬编码在中间)** — 用户明确改为要可配置;硬编码只是把"回收站在中间奇怪"换成"任何固定顺序都可能有人不满意"。
- **拖拽排序** — Flutter 长按拖拽在 ReorderableListView 之外(自绘底栏预览)实现成本高、触控误操作多;上移/下移按钮在 6 个可选项规模下完全够用且可测。
- **配置放进 Go 后端 config.db** — 该配置是纯 UI 偏好,与远端/挂载无关;SharedPreferences 与主题强调色、日志级别等既有 UI 偏好同渠道,同步到 Go 只增加格式与迁移负担。
- **返回键直接回首页再退出** — 用户选定"回上一 tab,无历史再退出"(标准移动行为);且首项可配置,固定回首页语义会随配置漂移。
- **无限层级历史** — 记录完整访问栈即可,不设上限;用户切 tab 次数天然有限,`back(visible:)` 过滤被移除项。

## Consequences

- 用户可在手机上自由组织底栏(例如只留 文件·首页·任务 三项),设置入口由"首页快捷入口或底栏"双路保底;约束违反在保存层与解析层双重拦截。
- 被移除的页面仍可通过首页快捷入口进入(回收站/设置等),页面本体都在 IndexedStack 中不销毁;底栏无匹配项不高亮的既有语义保留。
- `SidebarItem` 迁移使 `main_layout_page.dart` 不再定义公共枚举,引用方(bootstrap)改从 models 导入;桌面行为零变化(侧栏列表/视觉原样搬入 DesktopSidebar)。
- 验证:`flutter analyze` 零问题;152 个测试全过(新增 TabNavHistory 5 例、MobileNavPreferences 6 例、MobileHomePage 2 例);模拟器实际操作验收交用户。
