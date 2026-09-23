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
- **无边框基线（binding）**：Android **列表页**（文件管理的桶/对象/回收站移动列表、全局回收站、任务队列）内容不套箱形卡片容器——列表与空态直接落在页面背景上，行间用发丝分隔线保持节奏（`colorScheme.border` alpha 0.55、0.6px；表头下沿等既有分隔仍为 0.7/0.6，不强制统一）；**账号页与设置页的卡片容器按用户裁决保留**（账号块 `ShadCard`、设置索引分组卡与详情分区卡，2026-09-16 恢复）；`ShadCard` 等带边框容器在其余位置是桌面专属（含桌面窄窗 compact 分支，那里的卡片保留）。改动移动列表容器时按平台分支返回裸 `Column`/`Padding`，桌面路径保持原卡片外观。回归：`test/mobile_borderless_lists_test.dart` 与 `test/widget_test.dart` 的 Android 页面级 `ShadCard` 断言（列表页 findsNothing、账号/设置页 findsWidgets）。

## 导航与页面状态

- Android 底栏只承载 2–5 个一级目的地，设置始终可达；选中态用强调色和字重表达，未选中使用 muted 色。底栏外观、配置约束和实现见 [app_shell](app_shell.md)。
- 系统 Back 先消耗当前页面的层级（文件桶、目录、回收站或进行中的同步跳转），再回退可见 tab 历史，历史耗尽才退出。加载或错误状态同样必须保留可预期的返回路径。
- 列表首次加载、空态、错误和刷新状态必须保留当前位置与可恢复操作；不要用迟到请求或切换 tab 前的旧结果覆盖当前界面。

## 安全区、系统栏与抽屉

- 任何可触摸内容、页边距和横向菜单宽度都基于 `MediaQuery` 的左右/底部安全区计算；不得把手机宽度写死。横屏、刘海、手势导航栏和 IME 都不能造成裁切或横向溢出。
- 浅色 Android 首页的 `AnnotatedRegion<SystemUiOverlayStyle>` 必须位于 `ShadApp` 的首页 route 内，使用与背景匹配的深色系统栏图标；模态通过其嵌套 region 临时覆盖，不能用命令式 `SystemChrome` 留下跨 route 状态。
- 所有业务模态只经 `showAppModal*` 和 `AppShadDialog` 打开。Android 是全宽、贴底、顶角 20px 的 sheet；短内容收缩，长内容受键盘后可用高度的 90% 上限约束。滚动、SafeArea、焦点环和动画的完整契约见 [app_modal](app_modal.md)。
- 窄屏动作组用 `Wrap`、`OverflowBar` 或可滚动的单行容器；不要用固定宽度或不可换行的 `Row` 承载多个文字按钮。
- 窄屏实测途径（无窄屏真机时，按接近程度排序）：横屏分屏（约 220dp）> `adb shell wm density 640`（调完 `wm density reset`）> 系统单手模式（约 260dp）> 自由/迷你小窗（最极端）。两态选择模型（含两排动作条、头部计数、详情弹层）已于 2026-09-16 在 Xiaomi 13 Pro 迷你小窗实测通过；重占版式时至少按「动作条标签不截断、头部计数省略、详情长路径换行」三项复查。

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
- 顶层 tab 页共享 chrome：[mobile_page_chrome](../../../lib/widgets/mobile_page_chrome.dart) 提供 `MobilePageHeader`（稳定大标题 + 副标题 + 单一 48dp 动作入口）与 `showMobileActionSheet`（48dp 底部动作抽屉，文件管理同款实现）；[mobile_selection_chrome](../../../lib/widgets/mobile_selection_chrome.dart) 提供两态选择模型的选中态 chrome。账号/任务/回收站/设置页已按 2026-09-04 批次对齐该基线：SafeArea(bottom:false) + 16dp 边距、23sp 标题 + 13sp 副标题、触控目标 ≥48dp（含账号卡片动作、任务行内图标与选择控件、设置底部导航上移/下移钮）；设置页详情↔索引的系统 Back 链由 `MobileSettingsNavigation`（shell 持有）承接，先于 tab 历史消费。分享管理页与同步任务页在 Android 无底栏入口（不在 `kMobileBottomBarPool`），未做小屏适配；进入底栏池前必须先补。2026-09-15 第一批把五个底栏页（文件/账号/任务/回收站/设置）及文件管理页内桶回收站视图统一到无边框基线（见上），第二批把任务页与回收站页的页面级动作收进右上角单一 48dp 入口 + 底部抽屉（批处理运行中入口图标变 spinner、无可用动作时入口隐藏）；第三批选中动作条与第四批行级 `…` 抽屉先后落地又被取代，第五批按用户出示的百度网盘截图改为**两态选择模型（binding）**并沿用至今：浏览态行尾是 48dp 命中的空心选择圆点（`MobileRowSelectDot`）、无行首控件，行点击是主操作（文件=打开；回收站与任务=进入选中，任务明细一律经「详情」动作打开），长按=选中；进入选中态后页面头部整体变形为「取消 / 已选中 N 个 X / 全选」（`MobileSelectionHeader`，全选按过滤后可选集切换、全选中显示「取消全选」），行首 48dp 勾选控件接管、行点击切换选中，底部升起动作条（`MobileSelectionBottomBar`：图标上标签下、全量动作无「更多」——≤4 个单排，更多则两排均衡分列（5→3+2、6→3+3），标签用短动词、计数只在头部；动作集空不渲染、busy 整条变 spinner；全宽贴底、自带底部安全区）；**选中态下底部导航栏整体隐藏**（shell 经 `MobileSelectionActivity` 单例按「当前可见 tab 的报告」隐藏 `MobileNavigationBar`，页面在 build 里 report、仅在值变化时经微任务通知，页面 dispose 撤销报告——IndexedStack 隐藏页的陈旧报告由 shell 与当前 tab 组合消解）；页面级入口保持右上角单一 48dp 入口（文件视图 `+` 新建目录/上传、回收站 tab 与文件管理回收站视图的操作入口、任务页任务操作），仅浏览态可见（选中态头部被接管）。**单选动作条首项为「详情」**（文件、两个回收站与任务四个表面）：打开 `showMobileDetailSheet`（`MobileDetailSheet` 标签上值下、长路径无 maxLines 换行），展示系统已有的元信息（对象:名称/类型/大小/修改时间/完整路径/所属桶;回收站:名称/类型/大小/删除时间/原路径/所属桶;任务:操作/状态/所属桶/完整路径/本地路径/阶段或读取范围/依赖/错误——动态事件与传输 ID 仍是桌面展开面板内容）。**任务行在 Android 不再行内展开明细**：浏览态行点击=进入选中（任务无浏览态主操作，与回收站一致），明细全部经「详情」动作打开。桶行 `…` 抽屉不受影响（桶不可选）。搜索框与列表按文件管理页间距紧贴（头部后 14dp、筛选/搜索后 12dp）。回收站行 `onDoubleTap` 仍需置空（嵌套 tap 双触发抵消单击）。文件管理页系统 Back 先清空选择再回退位置。决策见 [Agent Note](../notes/implemented/architecture/2026-09-15-mobile-borderless-baseline.md)、[Agent Note](../notes/implemented/architecture/2026-09-15-mobile-header-action-sheet.md)、[Agent Note](../notes/implemented/architecture/2026-09-15-mobile-selection-action-bar.md)、[Agent Note](../notes/implemented/architecture/2026-09-15-mobile-row-overflow-drawer.md) 与 [Agent Note](../notes/implemented/architecture/2026-09-15-mobile-two-state-selection.md)。同日另一批把任务行格式与文件/回收站行统一：全宽发丝分隔线、标题 14sp w500；Android 任务行不再行内展开明细（80px 缩进契约回到桌面专属），桌面保留内联图标与明细 chevron。

**Known P2/P3 (review 2026-09-04):** P2 任务行最坏组合（spinner+状态徽标+取消+展开，行内动作 Android 48dp 化后固定宽约 343px）在 320dp 屏扣 16dp 边距会溢出约 23px，360dp 无碍——**已由 2026-09-15 行级抽屉批次在 Android 消解**（行内取消/重试/立即执行图标收进行抽屉），桌面不受影响，条目保留备查。P2 账号卡三按钮 320dp 下「桶管理」13sp 标签可用宽不足可能折行，可缩短标签或 maxLines 取舍。P3 账号卡 deleteProfile 动作沿用「退出」文案（与既有 toast 一致），破坏性语义弱化待产品定夺。（原 P3「回收站用例名 swap-title 未真正驱动选中态、任务页已选 N 项切换缺断言」已由 2026-09-15 选中动作条批次解决：行选中已可驱动且标题切换移除。）

**Known P2/P3 (review 2026-09-04 像素门控批次):** P2 `FittingFileNameText` 的可见截断串即读屏听到的内容（无独立完整名 semanticsLabel）——`semanticsLabel`/`Semantics` 包装会改变 render-object 形状，破坏既有 find.text 辅助函数的 `RenderParagraph` 强转；待读屏全名需求出现时再连同测试辅助函数一起演进。P2 网格卡片（file_grid_item）仍走纯字符预算 compactDisplayName，未接像素快路径（窄卡片收益低）。P3 系统 boldText/letterSpacing 覆盖未并入测宽（二阶偏差，默认设置无影响）。

**Known P2/P3 (review 2026-09-15 无边框批次):** P3 设置移动索引的分隔用 `Divider(height: 1)`（shadcn dividerTheme，border 全 alpha、1px），与基线发丝线（0.55/0.6）规格不一——保留现状，下次动设置索引时统一。P3 本批新增平台判断风格混用（`defaultTargetPlatform` vs `Theme.of(context).platform`，运行时与测试行为等价，后者沿用所在文件既有惯例）。P3 `mobile_borderless_lists_test.dart` 的内联 `ScrollController()` 不显式 dispose（与 `file_manager_object_browser_mobile_test.dart` 既有模式一致，树拆除时自动 detach）。P3 `transfers_page_remote.dart` 距 500 行上限余 5 行（拆分计划见 [remote_tasks](remote_tasks.md)）。

**Known P2/P3 (review 2026-09-15 行级抽屉批次，部分已被两态模型取代):** P3 批处理运行中任务行 `…` 静默无操作的问题已随行抽屉删除消失（两态模型下批处理运行中底部动作条整条变 spinner）。P3 本批 `dart format` 漂移未全量修复（仓库无 format 门禁，仅修新增漂移点）。

**Known P2/P3 (review 2026-09-15 两态选择批次):** P2 readOnly/下载能力门控失去浏览器级回归——对象浏览器旧用例（read-only 抽屉隐藏写动作、批量下载含被阻断目录）随行抽屉删除，页面级整机用例未接棒（widget_test 无 readOnly/supportsBrowserTransfers 场景，门控逻辑在 `file_manager_page_mobile_selection.dart` 的 `!readOnly` 与 `_canDownloadSelectedMobileObjects`）；待补页面级用例。P3 头部计数口径不一——文件管理按全量选中集、全局回收站/任务按过滤后可见选中数，搜索过滤掉部分选中项时同一头部会显示大于可见数的 N；后续统一为过滤口径。P3 桌面任务行内联图标/chevron 无存在性断言（历史亦无）——择机补 macOS 钉平台 findsWidgets。死参数 `_SelectionBarButton.enabled` 与 `global_trash_page_view.dart` 一处 dart format 漂移已同批修复。P3 回收站/任务 tab 的系统 Back 不先清空选择而是直接回退 tab 历史（shell 无页面级 Back 钩子；文件管理页已接 `_consumeMobileSelectionForBack`，「取消」按钮各页常驻；选中态下底栏已隐藏,Back 回到上个 tab 后底栏恢复、原 tab 的选中保留）。P3 选中态下页面级动作不可达（头部被选中态接管,与参考截图一致;退出选中即可达）。P3 单个对象的写动作（重命名/删除）在两排动作条的第二排（详情/打开/下载/分享 占第一排）；readOnly 目录仅剩 详情/打开/下载/分享。P3 任务详情 sheet 只含摘要元信息（动态事件记录与物理传输 ID 仍需桌面展开面板）。

**Known P2/P3 (review 2026-09-15 头部动作抽屉批次):** P2 回收站抽屉批量动作最初按未过滤的选中集门控，搜索排除全部所选时会死点——已按「过滤后仍可见的选中数」修复（与桌面一致）。P3 transfers 批量测试中 4 个门控用例依赖 binding 默认 android 平台、未显式 `debugDefaultTargetPlatformOverride`（沿用该文件既有风格，仅首个用例注释说明）；后续改写时建议显式钉住。P3 清空回收站图标已对齐文件管理抽屉的 `LucideIcons.trash`，但批量彻底删除仍用 `trash2`（行内彻底删除同款）——语义可辩护，暂不改。
