# App Shell — 窗口生命周期、导航、图标与响应式头部

## 桌面窗口关闭 / 托盘退出

自绘桌面 chrome 把关闭动作路由进 Flutter,使 Windows 能提供「隐藏到托盘」vs「退出」而不丢失 OS 级关闭手势。

- `lib/widgets/desktop_window_controls.dart` — 应用自有的最小化/最大化/关闭控件。关闭按钮与原生关闭请求调 `_confirmClose`;确认退出先 `await AppExitCleanup.cleanupMounts()`,再调 `WindowControls.exitApp()` 而不是 `WindowControls.close()`。确认对话框总是显示(即使零活跃挂载),让用户可以最小化/隐藏到托盘而不是退出;活跃挂载数改变文案解释「退出会卸载活跃根」而「后台运行」保留它们。动作行必须先 `double.infinity` 占满对话框宽度再用 `MainAxisAlignment.end`——固定窄宽会把按钮居中在宽警告对话框里而不是右下。
- `lib/services/app_exit_cleanup.dart` — 存储引导后的桌面 gateway 并合并退出时 `cleanupMounts` 调用。清理 30 秒超时,失败吞掉,不可用的过期挂载不会让不可见进程永久运行。
- `go/mount/manager.go` / `bridge/dispatch_mount.go` — `ActiveMountCount` 与 `get_active_mount_count` 暴露活跃 in-process 挂载会话数,供关闭警告而不探测每个桶。
- `lib/services/window_controls.dart` — 桌面窗口动作的 method-channel 门面。`close()` = 「请求关闭」,可被 Windows 托盘拦截;`exitApp()` = 用户已确认,原生宿主必须绕过托盘拦截。
- `windows/runner/flutter_window.cpp` / `flutter_window.h` — Windows 宿主 channel:每个 `WM_CLOSE` 回发 Flutter `requestClose`;托盘 Exit 发 `requestExit` 给 Flutter(挂载先清理);随后的 `exitApp` 调 `ExitApplication()` 并直接销毁窗口。正常确认退出与托盘 Exit 都先经原生 `hideForExit`(藏窗口 + 移除托盘图标),后台 `cleanupMounts` 完成后才 `exitApp`。Go `CleanupMounts` 停止每个会话;Windows Cloud Files backend 执行 `Disconnect` → watcher 关闭 → `Deregister`。隐藏到托盘/最小化刻意保持挂载活跃。强制进程终止仍依赖下次启动的过期清理(杀/崩后无 in-process 回调可跑)。
- `windows/runner/win32_window.cpp` / `win32_window.h` — 基础 Win32 窗口生命周期:`Close()` post `WM_CLOSE`;`Destroy()` 真正 teardown 并在 `quit_on_close_` 设置时 post quit。
- `linux/runner/my_application.cc` — Linux channel 实现:无托盘拦截;`exitApp` 等价 `close`;`shouldConfirmClose` 返回 false(保活动作是最小化,进程与挂载保持)。

**Gotchas(binding):**
- Windows 上确认退出**不要**用 `WindowControls.close()`——它 post `WM_CLOSE`,托盘激活时被有意拦截,会重开确认流程而不是退出。
- `close()` 只用于未确认的关闭请求(自绘关闭按钮预确认路径、Alt+F4、任务栏关闭)。
- `exitApp()` 用于确认后的显式「退出」,含原生托盘菜单退出动作。

## macOS 窗口生命周期与定位

- `macos/Runner/MainFlutterWindow.swift` — 主窗口(`NSWindow` 子类),持有 `MenuBarController`(托盘)。`awakeFromNib` 设透明标题栏、全尺寸内容视图、最小尺寸,下一 run loop tick 调 `applyDefaultWindowLayout()`。后者经 `resolvedInitialWindowSize()`(小屏缩放适配)解析尺寸,经 `centeredWindowFrame(for:)` 用 `self.screen ?? NSScreen.main` 居中。override `close()` 以确认对话框拦截(退出/隐藏到托盘/取消),除非 `allowsDirectClose`;`terminateWithoutConfirmation` 绕过对话框。
- `macos/Runner/AppDelegate.swift` — `applicationShouldTerminateAfterLastWindowClosed` 返回 false(窗口隐藏时保活);`applicationShouldHandleReopen` 调 `showYunjuanMainWindow()`(dock 点击重开);`applicationWillTerminate` 经 dlopen 调桥接 `cleanup_mounts` 退出时卸载桶。
- 顶层自由函数:`yunjuanMainWindow()` 找主 `MainFlutterWindow`;`showYunjuanMainWindow()` / `hideYunjuanMainWindow()` 经 `orderOut` / `makeKeyAndOrderFront` + `NSApp.activate` 显隐。
- 启动居中在 `self.screen ?? NSScreen.main`。`NSScreen.main` 是 macOS 认为的主显示器(系统设置 → 显示器里带菜单栏的);应用启动在「错误」屏幕时,修复在 macOS 显示设置,不在应用代码。
- 常量:默认 1160×740;最小 920×620;紧凑回退 840×560;默认不适配屏时按可见 frame 的 72% 宽 / 66% 高缩放。

## 导航结构

- `lib/models/sidebar_item.dart` — `SidebarItem` 枚举是桌面侧栏与移动底栏的单一事实来源;没有移动端 `home` 项,`SidebarItemInfo` 提供 icon / `desktopLabel` / `mobileLabel`。
- `lib/pages/main_layout_page.dart` — 根装配:桌面 `Row(DesktopSidebar + 内容)`;Android `PopScope + Scaffold(内容 + 底栏)`。内容为 `IndexedStack`,文件页固定在索引 0。`_selectItem` 是统一导航入口,移动端把访问记入 `TabNavHistory`。系统 Back 先交给活动文件页处理目录或桶回收站,再回退可见 tab,历史耗尽才调用 `SystemNavigator.pop`。
- `lib/pages/file_manager_page.dart` — 桌面文件管理入口与桌面表面,默认装配 `FileManagerWorkspace` 的桌面渲染。
- `lib/pages/mobile_file_manager_page.dart` / `mobile_file_manager_actions.dart` — Android 专属文件页、全宽搜索、触控列表、行尾操作、FAB 与操作抽屉;页面持有 `MobileFileManagerNavigation` 的 bind/clear 生命周期,不依赖桌面布局。
- `lib/pages/file_manager_workspace.dart` — 共享文件浏览运行时和公开 controller:持有桶/对象/回收站状态、加载和所有 mutation;controller 只暴露数据与命令,不返回桌面 Widget。移动与桌面复用它而不复用页面结构。
- `lib/widgets/mobile_file_manager_surface.dart` / `mobile_file_manager_browser.dart` — Android chrome 与单列浏览器:状态栏 `SafeArea`、48px 搜索、大触控行、行尾 `…`、无列表/网格切换。可点击行 idle 使用 `basic` cursor,hover 才切 `click`(见 [ui_rules](ui_rules.md))。
- `lib/state/mobile_file_manager_navigation.dart` — Android 文件页 Back 桥:当前页 bind 回调,销毁或替换时 `clear()`；避免以 Dart method tear-off 相等性作解绑判断。
- `lib/widgets/desktop_sidebar.dart` — 桌面侧栏(品牌标识 + SidebarPalette 渐变 + 装饰圆 + 导航项 + 传输状态入口);`_SidebarNavItem` 是 hover 正典(见 [ui_rules](ui_rules.md))。
- `lib/widgets/mobile_navigation_bar.dart` — 安卓底栏(取代 Material `NavigationBar`):纯 `ShadTheme` background 铺满物理底部(无渐变/装饰圆/胶囊),顶部一条全量 `colorScheme.border` 线与内容区分割(强度对齐参考设计 ≈ 白底 8% 黑),图标上文字下;选中态只有 `ThemeController` 强调色图标+文字和 w600,未选中 `mutedForeground`+w500。`MobileNavItem` 为泛型 value;`test/mobile_navigation_bar_test.dart` 锁定无渐变、分割线、强调色选中、muted 未选中与点击回调。
- `lib/state/mobile_nav_preferences.dart` — 底栏自定义配置(SharedPreferences key `mobile.bottom_bar_items`):可见项 + 顺序,默认 `文件·账号·任务·回收站·设置`;可选池仅有 fileManager/storage/transfers/trash/settings,约束 2–5 项且设置必须保留。旧数据的 `home` 会迁移为 settings,解析损坏数据回退默认。设置页「底部导航」节(仅 Android)写入,main_layout 监听重建。`test/mobile_nav_preferences_test.dart` 锁定默认/往返/迁移/约束。
- `lib/state/tab_nav_history.dart` — 移动端 tab 访问历史(纯逻辑):安卓返回键经 `PopScope` 回退上一个 tab(`back(visible:)` 跳过已从底栏移除的项),历史耗尽才允许退出应用。`test/tab_nav_history_test.dart` 锁定语义。
- `lib/pages/settings_page.dart` — 设置页,分组(通用设置、Windows 设置、关于)用**左垂直侧栏栏轨**(不是顶部 tab);「底部导航」卡(常规组,仅 Android)自定义底栏并保持设置可达。同步管理已从设置移除,完全在文件同步任务页;过期的 Windows「此电脑」条目卡与锚点已删除(`windowsThisPcEntryEnabled` 仅为兼容保留在配置模型)。

**Known P2/P3 (review 2026-08-29):** 底栏视觉两轮评审的 P2(分割线未铺满物理底部、去胶囊后触控目标回落 42dp)与 P3(圆角不一致、Semantics label 连读)已随定稿重设计解决(无渐变、无胶囊;全量 border 分割线;GestureDetector 内 `minHeight: 48`)。移动导航重构评审发现并同批修复:P0 返回键死锁(栈底项被移出底栏后 `back()` 永不弹空且 `canPop` 不重算——`back` 增加整条历史不可见时 reset(current) 语义,PopScope null 分支补 setState)、P1 设置节第 6 项静默截断(save 超限显式报错 + 设置节监听偏好异步 load 同步本地副本)、P2 ui_rules 正典指针未随 `_SidebarNavItem` 迁移更新。有意行为(不改):底栏 `selectedValue` 无匹配项时全部项不高亮;测试的无渐变断言扫描整棵 pumped 树,shadcn 内部若引入装饰渐变需收窄 finder。

**Known P2/P3 (review 2026-08-31):** P2 `FileManagerWorkspace` 仍是 `file_manager_page.dart` library 的 part，移动页因此暂时经该入口 import 共享工作区；controller 已避免布局泄漏，待公开契约明显扩张时再整体提升为独立 library。P2 尚未直接按 icon finder 断言 Android 页面不存在 `layoutGrid/list`，当前以无 `FileManagerActionBar`、独立 `MobileFileManagerBrowser` 和 widget 回归保护；若移动页加入新的工具栏，补上显式断言。

## 应用图标(桌面 + Android)

所有平台共享同一云+驱动器品牌图,各平台按其 shell 期望的格式与轮廓打包。

- `assets/brand/yunjuan_app_icon.svg` — 可编辑品牌图,不含平台特定 Windows 圆角遮罩。
- `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png` — 不透明 1024px 栅格,是 Windows 与 Android 图标生成的输入;macOS 应用自己的显示轮廓。
- `scripts/generate_windows_app_icon.ps1` — 应用默认 22.5% 圆角透明遮罩,高质量下采样,写 16/20/24/32/40/48/64/128/256px 的 PNG 背 ICO 层。
- `windows/runner/resources/app_icon.ico` / `windows/runner/Runner.rc` — 生成的 Windows 图标与 runner 资源绑定(启动器、Flutter 应用、任务栏、开始菜单、Explorer 消费)。
- `scripts/generate_android_app_icon.ps1` — 从同一 1024px 母版生成 Android 启动图标家族:legacy `ic_launcher.png`(方形全幅)+ `ic_launcher_round.png`(圆形遮罩)各 48/72/96/144/192px,以及自适应前景 `ic_launcher_foreground.png` 108/162/216/324/432px。前景经 `LockBits`(通道阈值 245)定位非白色作品边界并适配进 66/108 安全区,缩放与桌面一致。
- `android/app/src/main/res/mipmap-*/` — 各密度生成的启动 PNG;`mipmap-anydpi-v26/ic_launcher.xml` / `ic_launcher_round.xml` 自适应定义(引用 `@color/ic_launcher_background`,实现在 `values/ic_launcher_background.xml`,白底与母版画布一致);`AndroidManifest.xml` 引用 `@mipmap/ic_launcher` 与 `@mipmap/ic_launcher_round`。

**再生成流程:** 改品牌图 → 重生成 macOS 1024 栅格 → 仓库根跑 `generate_windows_app_icon.ps1` 并提交重生的 `app_icon.ico` → 跑 `generate_android_app_icon.ps1` 并提交重生 `mipmap-*` PNG。

**Gotchas:**
- macOS 1024 PNG 角落是不透明白。不要直接拷进 ICO 期望 Windows 套用 macOS 轮廓;Windows 圆角需要真 alpha。
- 圆角遮罩留在生成器里,不要烤进 `yunjuan_app_icon.svg`,macOS 等平台保持自己呈现的控制。
- 保留小 ICO 层——单个 256px PNG 强迫 Windows 运行时重缩,任务栏尺寸的圆角与品牌细节不可预测。
- `TextureBrush` 按原生像素采样。Android 圆形遮罩必须套在已缩放的方形上,绝不能套 1024 母版,否则只显示其左上角。
- 自适应前景只保留画布内部 ~66/108 安全区;把探测到的作品边界适配进该区复现桌面构图比例,不要把全幅母版画进前景。
- 品牌母版是宽构图(作品 ≈667×441 / 1024²)。legacy Android 图标刻意保留含白边的完整方形,与 Windows/macOS 呈现一致。

## 响应式页面头部操作区

所有列表式页面(任务队列/分享管理/回收站/文件同步/账号管理)共享同一头部模式:左 `Flexible(Column(title + subtitle))` + 右侧动作按钮。可见按钮多时(批量选中),标题列被挤压、副标题断句换行。共享 `PageHeaderActions` 在可用宽度低于阈值时把次要动作收进 `…` 溢出菜单(`ShadContextMenu`)。

- `lib/widgets/page_header_actions.dart` — `PageHeaderActions`(StatelessWidget):`primary`(始终布局)与 `secondary`(`List<SecondaryAction>`)。`LayoutBuilder` 比较 `constraints.maxWidth` 与 `overflowThreshold`(默认 520)。宽时全部内联渲染;窄时 primary + `_OverflowMenuButton`(镜像 `_BucketOverflowMenuButton` 模式:`ShadContextMenuController` + `DesktopContextMenuRegistry` 组 `_pageHeaderOverflowGroup` + `ShadGlobalAnchor`)。`SecondaryAction` 带 `label`、`builder`、`onPressed`、`enabled`。
- `lib/widgets/transfer_task_widgets.dart` — `TransferTaskSelectionActions` 包 `PageHeaderActions`。primary:已选 N 项徽标 + 批量开始 + 批量取消;secondary:移除记录/清空选择/清空已完成。
- `lib/pages/transfers_page.dart` — 头部 `Row` 简化:`Flexible` 标题列 + 单个 `TransferTaskSelectionActions`;副标题 `maxLines: 2`。
- `lib/pages/share_management_page.dart` — 选中:primary 已选 N 项 + 删除选中,secondary 取消选择;未选中:primary 刷新。
- `lib/widgets/global_trash_controls.dart` — `GlobalTrashHeaderActions`:选中态只有 已选 N 项 + 批量恢复 + 批量彻底删除(头部无 清空选择,经行/头复选框取消选择);两种状态用 42px 最小动作区高度(Shad 常规 outline 按钮比常规 ghost/destructive 高 2px),选中批量按钮也用常规尺寸;未选中:primary 刷新,secondary 清空回收站。`test/global_trash_header_actions_test.dart` 锁定 360px 头部宽度的等高、单行、隐藏动作行为。
- `lib/pages/global_trash_page_view.dart` / `file_sync_tasks_page.dart` / `cloud_storage_page.dart` — 标题列 `Expanded` → `Flexible(fit: FlexFit.tight)`;副标题 `maxLines: 2, overflow: ellipsis` 硬底线。

**Gotchas(binding):**
- 标题列必须是 `Flexible(flex: 1, fit: FlexFit.tight)` 而不是 `Expanded`,右侧 `PageHeaderActions` 的 `Wrap` 才能被 `LayoutBuilder` 对真实剩余宽度测量;`Expanded` 让标题吃满空间,动作永远看不到宽度约束。
- `_OverflowMenuButton` 必须是持有 `ShadContextMenuController` 与 `_menuAnchorOffset` 的 StatefulWidget;`ShadButton.outline` 的 `onPressed` 经按钮 `GlobalKey` + `localToGlobal` 计算锚点再 `_controller.show()`。
- 单按钮头部(文件同步 新建配置、账号管理 新增账号)刻意**不用** `PageHeaderActions`(不会溢出),但 `Flexible` 标题列 + 副标题 `maxLines` 底线仍统一适用。
