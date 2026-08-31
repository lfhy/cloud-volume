# Agent Note: 移动端可配置底栏、文件首屏与返回键历史栈

Status: implemented

## Problem

手机上的远端文件操作需要把文件作为抵达应用后的直接入口。独立首页会把用户先带到概览，再要求一次跳转才能搜索、进入桶或上传；同时小屏不能照搬桌面文件页的导航与返回逻辑。底栏仍需允许用户按日常工作流调整项目和顺序，但不能让设置入口消失。

## Decision

- **配置驱动底栏:** `lib/state/mobile_nav_preferences.dart` 把可见项与顺序持久化到 SharedPreferences(`mobile.bottom_bar_items`),默认 `文件·账号·任务·回收站·设置`。可选池为 fileManager/storage/transfers/trash/settings;约束为 2–5 项且必须保留 settings。解析损坏或非法数据回退默认；历史数据中的 `home` 迁移为 settings。
- **文件首屏:** Android 没有 `SidebarItem.home` 或 `MobileHomePage`;`MainLayoutPage` 的首个 IndexedStack 子项是 `MobileFileManagerPage`。设置仍在底栏并可由文件页顶部按钮打开。
- **设置节(移动端专属):** `SettingsMobileNavSection` 挂在设置页常规组,只在 Android 渲染。它使用开关、上移/下移按钮和恢复默认管理底栏,在保存层与 UI 层共同拦截违反约束的修改。
- **返回优先级:** `MobileFileManagerNavigation` 让活动文件页先消费 Android Back;桶回收站关闭到文件、子目录返回上级、桶根返回桶列表。文件页未消费时，`TabNavHistory` 才回退仍可见的底栏项目，历史耗尽后退出应用。

## Alternatives considered

- **保留独立首页作为默认首屏** — 概览和快捷入口会额外占用一次导航，不能满足以文件和搜索为中心的移动工作流。
- **固定底栏顺序** — 用户已需要按任务频率调整入口；五个项目规模小，开关和上下移动比触控拖拽更稳且可测。
- **允许移除设置** — 会使恢复底栏配置没有可靠入口，也会让设备上的全局设置难以访问。
- **系统 Back 直接按 tab 或直接退出** — 会跳过用户正在浏览的目录或回收站，破坏移动文件浏览的层级直觉。

## Consequences

- Android 启动后立即显示文件和常驻搜索，不存在可配置或可恢复的首页页面。
- 移动端底栏仍可缩减到 2–5 项，但设置永远可达；旧偏好无须手工重置。
- 文件级 Back 与 tab 级 Back 有明确优先顺序，`test/mobile_file_manager_navigation_test.dart`、`test/tab_nav_history_test.dart` 和 `test/widget_test.dart` 覆盖导航桥、历史和系统退出路径。
- 文件页视觉与业务工作区的分离由 [移动文件页呈现决策](../architecture/2026-08-31-mobile-file-manager-presentation.md) 持有。
