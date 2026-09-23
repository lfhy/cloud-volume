# Agent Note: Android 顶层页共享 chrome 与设置页 Back 桥

Status: implemented

## Problem

Android 端只有文件管理页有专门的小屏呈现；账号、任务、回收站、设置四个底栏可达页各自维持桌面边距(36/56dp)、无 SafeArea、触控目标远小于 48dp、标题层级不稳定(回收站选中时标题整个消失)。而文件管理的移动动作抽屉实现(`_showMobileActionSheet`)是它页内私有,其他页要复用只能复制。设置页有「索引 → 详情」两级结构,但系统 Back 不认识它:在详情页按 Back 会直接退 tab 历史甚至退出应用。

## Decision

1. **共享 chrome**:把文件管理的移动动作抽屉提取为 `lib/widgets/mobile_page_chrome.dart` 的 `showMobileActionSheet` + `MobilePageAction`,并新增 `MobilePageHeader`(稳定大标题 23sp + 副标题 13sp + 单一 48dp 动作入口,无动作时隐藏入口)。文件管理页改为薄委托,渲染逐项等价。账号/任务/回收站/设置四页统一对齐该基线:`SafeArea(bottom: false)` + 16dp 边距、48dp 触控(账号卡动作、任务行内图标/选择框/翻页钮、回收站 compact trailing、设置底栏自定义上移/下移钮)、账号卡文案中文化并修复禁用标题乱码。
2. **设置 Back 桥**:新建 `lib/state/mobile_settings_navigation.dart`,采用与 `MobileFileManagerNavigation` 相同的 **bind/clear 回调契约**——页面在进入详情时 `bind(collapse)`,收起或销毁时 `clear()`;shell 的 `_handleAndroidBack` 在 fileManager 分支之后、tab 历史之前询问 `consumeBack()`,返回 true 即吞掉本次 Back。`_selectMobileTab` 是 `_mobileTab` 唯一赋值入口,保证 UI 与桥状态不漂移。
3. **桌面零污染**:任务页队列头部的 48dp 触控高、居中包裹与 23sp 标题全部以 `_androidCompactQueueHeader` 为门;回收站标题 22→23 仅 Android;设置页 Android 分支移出桌面 `Padding(56/36)` 之外。

## Alternatives considered

- **`MobileSettingsNavigation` 用 ChangeNotifier + setInDetail/consumeBack 内部翻转状态** — 首版实现,P0 评审证伪:全库无人 `addListener`,consumeBack 返回 true 但 UI 不动,状态机反向失同步,第二次 Back 直接落 tab 历史把停留在详情页的用户切走。教训:shell↔页面桥接必须用 bind/clear 回调让页面自己改状态,不能让桥自持状态指望别人监听。
- **每页复制文件管理的抽屉实现** — 三处重复的宽度公式与安全区计算,后续改 48dp 契约要同步四份;提取为共享函数后文件管理是薄委托。
- **把四页改成独立 `Mobile*Page` 入口(文件管理模式)** — 四页无独立业务状态与返回栈,`IndexedStack` 槽位共用 widget、页内 `defaultTargetPlatform` 自检已够;为它们建独立页面类只会复制参数传递。
- **回收站选中态维持标题消失换宽度** — 标题位置跳动违反稳定层级基线;改为单行「已选 N 项」(与任务页选中态同款)。
- **分享管理/同步任务页一并适配** — 两者不在 `kMobileBottomBarPool`,Android 无任何入口可达,先在 mobile_ui.md 记录事实;进入底栏池前再适配,避免为不可达页面维护移动代码。

## Consequences

- 移动 chrome 契约(48dp 抽屉行、16dp 图标内距、宽度公式)单点维护于 `mobile_page_chrome.dart`;后续新页(如分享管理若进入底栏)直接复用。
- 设置详情 Back 先于 tab 历史消费;页面销毁(dispose)即 clear,不会持有失效回调。
- `LucideIcons` 继续经 `shadcn_ui` 重导出使用(不新增直接依赖):曾尝试把 `lucide_icons` 提为 pubspec 直接依赖,但 pubspec 变更会使整个 lockfile 失效并触发全量重解析(本机经 pub.flutter-io.cn 镜像重解析到 file_picker_platform_interface 3.3.0 等新传递版本,9 个文件管理域用例行为漂移失败);保持 pubspec 不动则 HEAD 锁有效,CI 与提交状态一致。
- `cloud_storage_account_list.dart` 按展示件拆出 part 文件 `cloud_storage_account_card.dart`,两文件均在 500 行 binding 内。
- 遗留(记录于 TODO 统一测试阶段):任务行最坏组合在 320dp 屏可能横向溢出 ~23px;账号卡三按钮 320dp 下标签可能折行;回收站/任务页选中态的「已选 N 项」切换尚未有 widget 断言;经 pub.flutter-io.cn 镜像的本地全量 widget_test 会因传递依赖重解析漂移(file_picker_platform_interface 3.0.1→3.3.0 等行为变化)失败 9 个文件管理域用例——CI(pub.dev + HEAD 锁)不受影响,待 file_picker 锁版本升级时一并消化。

## Verification

- `flutter analyze` 干净(仅 2 条既有 deprecation info)。
- `test/mobile_page_chrome_test.dart`:头部无动作时无入口、动作入口 48dp 且语义命名、抽屉打开/触发;`MobileSettingsNavigation` bind/consume/clear 语义。
- `test/widget_test.dart` 四个新 android 用例:账号页头部/48dp 动作/中文文案、设置页详情进入→`handlePopRoute()` 真实驱动收起回索引、任务页副标题与 48dp 批量钮、回收站副标题;连同修复 file_picker 接口升级遗留的 fake 编译错误后全部通过。
- 真机统一验证(滚动、横屏安全区、真实数据流)列入 TODO 待办。
