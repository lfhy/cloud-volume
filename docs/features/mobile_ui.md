# Mobile UI — Android 专属设计要点(binding)

所有 Android/移动端 UI 改动在开始布局、搜索或编码前先读本页；它是跨特性的设计检查清单。具体组件的代码归属和精确契约仍以 [app_shell](app_shell.md)、[ui_rules](ui_rules.md)、[app_modal](app_modal.md) 与 [android_dev](android_dev.md) 为准，不能把这些细节复制回本页。

## 适用范围与实现边界

- 移动呈现以 `!kIsWeb && defaultTargetPlatform == TargetPlatform.android` 判断；不要用 `dart:io Platform.isAndroid`，否则 widget 测试不能用 `debugDefaultTargetPlatformOverride` 覆盖平台分支。
- 移动端可以有独立 chrome、信息密度和触控容器，但复用已有 workspace/controller 的数据、mutation 和导航状态；不得为适配小屏复制业务状态或异步请求逻辑。
- 先确认能力是否在 Android 有完整工作流。桌面专属的窗口、挂载、拖放、鼠标右键和网格开关不因“看起来一致”而出现在移动端。
- 页面标题使用完整的产品功能名（例如「文件管理」）；底栏可使用较短标签（例如「文件」）。首页副标题沿用该功能在桌面端批准的说明，进入后的副标题只表达当前位置、范围或状态，不重复标题。

## 信息层级、触控与列表

- 标题、当前位置、搜索和主要内容保持稳定的自上而下阅读顺序；不要把桌面面包屑、密集工具栏或多个行内图标直接压缩到手机页面。
- 每个可点按的操作最小为 **48×48dp**；相邻独立目标至少留 **8dp** 间隔。若控件视觉较小，仍要用 `SizedBox` 等保留完整触控区域。
- 默认采用 4/8dp 间距节奏，并沿用页面已有的左右安全留白；新列表无专门规格时，图标与按下态边缘至少留 16dp 呼吸空间。
- 触发整行操作时，按下态覆盖完整触控行，但不得让图标、文字、尾部操作或行高跳动。图标列与标签列分别固定对齐；文字从标签列左端开始，行内垂直居中。
- 页面有多个随位置变化的操作时，不在搜索框下另占一条横向操作栏；用右上角带语义名称的 48dp 图标入口，经 `showAppModal` 打开底部抽屉列出可用动作。没有可用动作时隐藏入口，抽屉行仍保持 48dp 命中区。
- 手指没有持续 hover。移动端不可把桌面 hover、右键或 tooltip 当作发现机制；Android 上的 `AppTooltip` 必须降级为 `Semantics(label: message, child: child)`，绝不构造 `ShadTooltip`。Shad 的触摸 tooltip 会把 tap 当作 hover 切换，系统 Back 或 route 切换不会补发 leave，提示及背景洗色会残留。图标按钮必须有可读的 `Semantics` 标签，复杂动作放进命名清楚的菜单或抽屉。
- 文字遵循主题字体与动态字号；正文优先不小于 16sp，紧凑说明不低于 12sp。单行位置/名称可省略号截断，但不能溢出或把关键操作挤出屏幕。
- **文件名截断契约**：移动端文件列表的文件名展示统一走 `FittingFileNameText`（`lib/widgets/fitting_file_name_text.dart`）——**像素感知快路径**：名字宽度（TextPainter 实测，按该行自己的可用宽度）放得下就原样显示（19 字符的 `default_blurred.png` 在宽行完整显示）；放不下才退到 `compactDisplayName`（头+尾+扩展名，中段 `...`；`lib/utils/display_name.dart`）的字符预算截断——宽紧凑行（对象/回收站/目录选择器，约 250–300dp）默认 18，任务行（最窄，约 110dp）传 14。桌面宽列表保持完整文件名（桌面窄窗宽度门表面走同一链路）。辅助技术始终拿到完整名（Semantics label）。已知限制：字符预算按 UTF-16 码元，纯 CJK 长名退到截断后仍可能被外层尾省略截掉扩展名。回归见 `test/fitting_file_name_text_test.dart`、`test/display_name_test.dart` 与目录选择器测试。
- **列表行字号基线**：移动端文件类列表行（对象/回收站/任务）标题 14sp、副标题/元信息 12sp，跨页一致（`RemoteTaskRow` 经 `defaultTargetPlatform` 分支对齐 `FileListTile` compact 的 14/12）；桌面维持 13/11 密集节奏。状态徽标 chip 等 10.5sp 小字属行内 chrome，不在此基线内。

## 导航与页面状态

- Android 底栏只承载 2–5 个一级目的地，设置始终可达；选中态用强调色和字重表达，未选中使用 muted 色。底栏外观、配置约束和实现见 [app_shell](app_shell.md)。
- 系统 Back 先消耗当前页面的层级（文件桶、目录、回收站或进行中的同步跳转），再回退可见 tab 历史，历史耗尽才退出。加载或错误状态同样必须保留可预期的返回路径。
- 列表首次加载、空态、错误和刷新状态必须保留当前位置与可恢复操作；不要用迟到请求或切换 tab 前的旧结果覆盖当前界面。

## 安全区、系统栏与抽屉

- 任何可触摸内容、页边距和横向菜单宽度都基于 `MediaQuery` 的左右/底部安全区计算；不得把手机宽度写死。横屏、刘海、手势导航栏和 IME 都不能造成裁切或横向溢出。
- 浅色 Android 首页的 `AnnotatedRegion<SystemUiOverlayStyle>` 必须位于 `ShadApp` 的首页 route 内，使用与背景匹配的深色系统栏图标；模态通过其嵌套 region 临时覆盖，不能用命令式 `SystemChrome` 留下跨 route 状态。
- 所有业务模态只经 `showAppModal*` 和 `AppShadDialog` 打开。Android 是全宽、贴底、顶角 20px 的 sheet；短内容收缩，长内容受键盘后可用高度的 90% 上限约束。滚动、SafeArea、焦点环和动画的完整契约见 [app_modal](app_modal.md)。
- 窄屏动作组用 `Wrap`、`OverflowBar` 或可滚动的单行容器；不要用固定宽度或不可换行的 `Row` 承载多个文字按钮。

## 视觉反馈与无障碍

- 状态反馈应在 100ms 内可见，并只改变中性背景或已有的明确选中态；不得通过改字重、图标颜色、边框宽度或动态插入尾部元素造成布局跳动。hover 规则与 `ListInteractionColors` 的使用见 [ui_rules](ui_rules.md)。
- 普通文字与背景至少满足 4.5:1 对比度，UI 边界和图标至少 3:1；不得只靠颜色表达状态，需保留图标、标签或文字。
- 焦点顺序遵循从上到下、从左到右；每个可交互图标都需要语义名称，动态状态变化应可被辅助技术理解。

## 改动前检查与验证

1. 先确认此能力是否应在移动端出现，以及它是否复用而非复制已有运行时。
2. 检查 48dp 触控、8dp 目标间距、16dp 列表内侧呼吸空间，以及图标/文字列的稳定对齐。
3. 在普通竖屏、横屏安全区、键盘打开和长文字/大字号下检查不裁切、不溢出，且 Back、抽屉关闭和加载/错误恢复正确。
4. 为变更补最窄 Android widget 回归；测试显式设置 `debugDefaultTargetPlatformOverride`，并在测试体 `try/finally` 中重置。截图只用于设计反馈，不代替自动化验证。
5. 触控图标若有桌面提示文本，回归须确认 Android 没有 `ShadTooltip`，仍有同名 `Semantics`，并覆盖点击后由系统 Back 或导航关闭的路径。

## 现有正典与参考实现

- 文件管理的移动呈现、底栏、Back 栈、系统栏和移动菜单：[app_shell](app_shell.md)。
- 全局 hover、loading 与列表交互色：[ui_rules](ui_rules.md)。
- Android 底部抽屉、安全区、IME、滚动与模态动画：[app_modal](app_modal.md)。
- Android 运行、模拟器、APK 与移动端能力边界：[android_dev](android_dev.md)。
- 顶层 tab 页共享 chrome：[mobile_page_chrome](../../../lib/widgets/mobile_page_chrome.dart) 提供 `MobilePageHeader`（稳定大标题 + 副标题 + 单一 48dp 动作入口）与 `showMobileActionSheet`（48dp 底部动作抽屉，文件管理同款实现）。账号/任务/回收站/设置页已按 2026-09-04 批次对齐该基线：SafeArea(bottom:false) + 16dp 边距、23sp 标题 + 13sp 副标题、触控目标 ≥48dp（含账号卡片动作、任务行内图标与选择控件、回收站 compact trailing、设置底部导航上移/下移钮）；设置页详情↔索引的系统 Back 链由 `MobileSettingsNavigation`（shell 持有）承接，先于 tab 历史消费。分享管理页与同步任务页在 Android 无底栏入口（不在 `kMobileBottomBarPool`），未做小屏适配；进入底栏池前必须先补。

**Known P2/P3 (review 2026-09-04):** P2 任务行最坏组合（spinner+状态徽标+取消+展开，行内动作 Android 48dp 化后固定宽约 343px）在 320dp 屏扣 16dp 边距会溢出约 23px，360dp 无碍——真机统一测试时验证，必要时行内动作收进溢出菜单。P2 账号卡三按钮 320dp 下「桶管理」13sp 标签可用宽不足可能折行，可缩短标签或 maxLines 取舍。P3 回收站用例名 "swap-title on select" 未真正驱动选中态（名实不符）；任务页「已选 N 项」切换同样缺 widget 断言。P3 账号卡 deleteProfile 动作沿用「退出」文案（与既有 toast 一致），破坏性语义弱化待产品定夺。

**Known P2/P3 (review 2026-09-04 像素门控批次):** P2 `FittingFileNameText` 的可见截断串即读屏听到的内容（无独立完整名 semanticsLabel）——`semanticsLabel`/`Semantics` 包装会改变 render-object 形状，破坏既有 find.text 辅助函数的 `RenderParagraph` 强转；待读屏全名需求出现时再连同测试辅助函数一起演进。P2 网格卡片（file_grid_item）仍走纯字符预算 compactDisplayName，未接像素快路径（窄卡片收益低）。P3 系统 boldText/letterSpacing 覆盖未并入测宽（二阶偏差，默认设置无影响）。
