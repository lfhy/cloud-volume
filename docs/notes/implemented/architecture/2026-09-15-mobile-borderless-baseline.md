# Agent Note: Android 无边框移动基线（参照文件管理页）

Status: implemented

## Problem

2026-09-04 批次把账号/任务/回收站/设置四页对齐到共享移动 chrome 后,页面内容仍各自套着桌面遗留的箱形卡片边框:任务列表与空态包在 `ShadCard` 里、账号卡是 `ShadCard`、设置索引分组与详情分区是 `ShadCard`、两个回收站浏览器(全局页 + 文件管理页内桶回收站)也是 `ShadCard`。而参照页——文件管理页——的移动桶/对象列表早就直接落在页面背景上(行间发丝分隔线)。同为底栏可达页,视觉上却分成「平铺列表页」和「卡片盒子页」两派;文件管理页自身也不一致:桶/对象列表平铺,页内回收站视图却是盒子。

## Decision

以文件管理页移动列表为正典,Android 上页面内容一律不套箱形卡片容器(mobile_ui.md「无边框基线」binding):

- 任务页:`_buildRemoteList` 抽出 `listBody`,`_androidCompactQueueHeader`(即 Android)直接返回,桌面继续包 `ShadCard(padding: 4)`;`_buildEmptyState` 同样按平台分支,Android 空态与 `FileManagerEmptyState` 同构(直接 Center)。
- 账号页:`_AccountCard` 的 `mobileLayout` 分支返回 `Padding(14)` 裸块,桌面网格/表格保持卡片;`_buildMobileList` 的分隔符由 12dp 空隙改为发丝线(`colorScheme.border` alpha 0.55、0.6px,与 `FileListTile` 行分隔同规格)。
- 设置页:移动索引(Android 专属方法)直接渲染 ListTile + Divider 列;`_buildCard` 增加 Android 分支渲染无边框「标题+内容」块,桌面双栏布局不变。
- 回收站:`GlobalTrashBrowser`(其 `compact` 恰好等于 Android)与 `FileManagerTrashBrowser._buildList`(平台判断与宽度 compact 判断分离)都在 Android 上跳过卡片包装。

桌面(含桌面窄窗 <600dp 的 compact 分支)渲染路径逐字节不变——卡片边框是桌面信息密度的一部分,不动。

## Alternatives considered

- **全局改 ShadCard 主题去掉边框(如自定义 cardTheme)** — 一处配置影响所有平台的卡片,桌面外观会被连带改掉;且 shadcn_ui 版本升级时主题字段漂移风险大。按平台分支返回不同容器,桌面路径零风险。
- **只改四个底栏页,不动文件管理页内的桶回收站视图** — 参照页自身就不一致(桶/对象平铺、回收站是盒子),留着它等于给下一个适配留一个错误样板;顺手统一成本只有几行。
- **保留卡片背景色、只去边框** — 用户要求是「参照文件管理页」,那里的行就在页面背景上;半途保留浅色卡底会形成第三种风格。
- **bootstrap 向导页一并去边框** — 首跑向导是独立流程,不在底栏页集合内,卡片是其步骤容器的语义结构;超出自本范围,如需要另起变更。

## Consequences

- Android 五个底栏页(文件/账号/任务/回收站/设置)及文件管理页内所有列表视图统一为平铺 + 发丝分隔线;`ShadCard` 在这些页面子树中 Android 下 `findsNothing` 可作回归断言。
- `FileManagerTrashBrowser` 的平台分支刻意不复用 `compact`(它含 `maxWidth < 600` 的桌面窄窗),避免桌面窄窗意外丢卡片。
- 设置移动索引的透明 `Material` 包装保留(不再有 ShadCard DecoratedBox,但它继续保证 ListTile 墨水可见,注释已改写)。
- 无本地 Flutter SDK 的机器(本批次的 macOS 检出)只能静态验证;评审与真机验证承载回归责任(见 Verification)。
- 分享管理页(Android 不可达)与 bootstrap 向导仍保留卡片;进入移动可达集合时须先补无边框处理。

## Verification

- 新增 `test/mobile_borderless_lists_test.dart`:两个回收站浏览器与账号列表在 Android `findsNothing` ShadCard、桌面(macOS 覆盖)`findsOneWidget` 双向钉住;`test/widget_test.dart` 四个既有 Android 页面用例补 SettingsPage/CloudStoragePage/TransfersPage/GlobalTrashPage 子树级 findsNothing 断言(索引与详情各一处)。
- 2026-09-15 当日在本机构建完整 Android 工具链后复验(macOS 镜像引导变体,记录见 [android_dev Gotchas](../../../features/android_dev.md)):`flutter analyze` 干净(仅 2 条既有 deprecation info),`flutter test` 全量 247 项全部通过(含上述新用例),`flutter build apk --release --split-per-abi` 产出含 arm64 Go 桥的 release APK(`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`)。
