# Agent Note: Android 文件管理分离呈现并共享运行时

Status: implemented

## Problem

Android 文件页曾在两种极端之间摇摆：一套独立触控页面会漂移，直接呈现桌面面包屑和操作栏又不符合小屏层级和触控交互。后者还把桶设置暴露为行内图标，且 Android edge-to-edge 透明系统栏没有明确图标颜色，时间、信号和电量可能与浅色背景混在一起。

## Decision

`FileManagerPage` 和 Android 的无状态入口 `MobileFileManagerPage` 都装配同一个 `FileManagerWorkspace`。它仍是 bucket / 对象 / 回收站数据、请求、mutation、同步 ticket 和 Android 文件位置返回栈的唯一拥有者；桌面通过 `file_manager_page_presentation.dart` 呈现面包屑和操作栏，Android 通过 `mobile_file_manager_presentation.dart` 独立呈现「文件 + 当前位置」页头、常驻搜索和右上 48dp `+` 操作入口。

Android 固定紧凑列表，不显示网格切换或挂载、卸载、打开挂载目录。桶行和对象行都只留 48dp 行尾 `…`；它经 `showAppModal` 显示底部抽屉。桶抽屉在同一 action model 中提供打开存储桶、桶设置、回收站和 WebDAV 等可用项，桶设置不再作为行内图标。对象抽屉保留预览/打开、下载、分享和可写时的复制、移动、重命名、删除；也可由长按打开。多选对象以「已选 N 项」为标题并提供批量动作，目录下载只在递归能力存在时显示。页面级的回收站、新建目录与上传也不占搜索框下方的横向栏：右上带「文件操作」语义的 48dp `+` 根据当前位置打开同一风格的动作抽屉；桶回收站则显示返回文件和可用的清空操作。Android 的 `AppTooltip` 统一只提供语义标签而不构造 `ShadTooltip`：后者会把触摸 tap 解释为 hover 开关，系统 Back 或 route 切换没有匹配 leave 事件，视觉状态会残留。已显式语义化的桶/对象 `…` 与使用 `AppTooltip` 的顶栏返回因此都保留可读名称而没有触摸 tooltip。进入桶、目录或桶回收站后，48dp 顶栏返回按钮与系统 Back 共用位置栈并覆盖加载/错误状态。`ShadApp` 首页 route 内的根 `AnnotatedRegion<SystemUiOverlayStyle>` 明确浅色背景上的深色系统栏图标；模态的嵌套 region 临时覆盖该样式，避免命令式系统栏设置泄漏到下一个 route。

`FileManagerWorkspace` 直接绑定 `MobileFileManagerNavigation` 的系统 Back 回调，并在销毁或导航实例替换时 `clear()`，不再经允许自建视图的 controller 暴露文件管理状态。Android 的 bucket 列表、桶+prefix、桶回收站位置栈仍在 workspace 内：目标在请求前提交，加载或错误状态也优先消耗 Back；同步跳转和列表请求继续使用 ticket、epoch 与 listing generation 丢弃迟到结果。

## Alternatives considered

- **保留原先的独立触控业务页** — 它会复制加载、mutation 和异步安全逻辑，长期与桌面脱节；独立的只是一层呈现。
- **在 Android 复制桌面 widget 树** — 小屏会得到桌面面包屑、弹出搜索和密集操作栏；改用独立移动 chrome，同时保留底层 runtime 单一事实来源。
- **把桶设置继续放在行内** — 行尾有多个操作时会降低主要导航行的可扫读性；移动端统一收进 `…` 抽屉，按需展开。
- **保留搜索框下方的横向操作行** — 三个上下文动作会挤占首屏高度，长标签还需横向滚动；改为右上单一入口和全宽抽屉行，保留 48dp 命中区与完整文字。
- **在移动端渲染 `ShadTooltip`** — 触控没有持续 hover，点击后再由系统 Back 或导航关闭表面不会向原按钮发送第二次事件，tooltip 的触摸 hover 状态会停留；`AppTooltip` 在 Android 统一降级为语义标签，保留 48dp 按钮和语义名称即可满足辅助功能需求。
- **直接调用 `SystemChrome` 切系统栏** — route 关闭后容易留下旧状态；通过首页 route 与模态嵌套的 `AnnotatedRegion` 随 widget 生命周期恢复。
- **取消 Android 的文件位置栈以完全等同桌面** — 系统 Back 会过早退到 tab 或退出应用；该导航语义不改变视觉 UX，继续保留。
- **在 Android 保留桌面视图切换和挂载入口** — 这些能力依赖桌面窗口/文件系统边界，移动端没有对应工作流；固定列表并隐藏入口可以保持组件树一致而不暴露不可用动作。

## Consequences

- 文件管理运行时变更同时服务桌面和 Android；视觉、排版、可见入口和触控容器由两个呈现层独立演进。
- Android 专用代码可维护 chrome、桶/对象紧凑行和动作抽屉，但不得复制数据加载、mutation、同步跳转或文件位置栈。
- 页面级文件动作只由右上 `+` 打开；动作列表根据桶、目录或桶回收站状态生成，按钮与每一抽屉行均保持 48dp。
- Android 文件位置栈、同步 ticket 和 listing generation 继续隔离异步导航，不影响桌面面包屑和鼠标工作流。
- `FileManagerWorkspace` 仍由 `file_manager_page.dart` library 承载；需要跨 feature 复用时再整体提升为独立 library。

## Testing

`test/app_tooltip_test.dart` 锁定 Android 只得到语义标签、没有 `ShadTooltip`，桌面仍保留可视提示；`test/widget_test.dart` 断言 Android 不出现桌面 `FileManagerActionBar` 或 `FileManagerBreadcrumbBar`、使用常驻搜索与独立页头、桶行没有行内桶设置图标，二级页的右上 `+` 没有触摸 tooltip、保留「文件操作」语义并以 48dp 抽屉行显示回收站、新建目录和上传，非空桶回收站也经同一入口进入既有清空确认框，二级页返回按钮没有触摸 tooltip，`…` 底部抽屉保留桶设置且没有挂载项；打开抽屉后经系统 Back 关闭时，不得残留操作表面。`test/file_manager_object_browser_mobile_test.dart` 锁定对象紧凑行、48dp 行尾和选择命中区、长按/系统 Back、只读动作过滤、多选目录下载门控及窄屏大字号抽屉。它们同时锁定列表模式、已加载/加载中二级页的顶栏 Back、文件 Back、同步跳转、分页和 mutation 的迟到响应。`flutter analyze` 与完整 Go / Flutter 测试集验证呈现分离不改变共享运行时。
