# Agent Note: Android 文件管理的独立呈现层

Status: implemented

## Problem

桌面文件管理页以面包屑、密集操作栏、列表/网格切换、鼠标输入和桌面拖放为中心。把这套结构压缩到 Android 会挤占内容与搜索空间，也会令后续移动交互改动必须穿过桌面页面的私有状态。用户要求 Android 页面与桌面页面分开并单独维护，同时文件加载、上传、删除和回收站等语义仍必须一致。

## Decision

`FileManagerPage` 是桌面入口，`MobileFileManagerPage` 是 Android 专属 Stateful 页面。移动页自有 `MobileFileManagerSurface`、`MobileFileManagerBrowser` 与 `mobile_file_manager_actions.dart`，负责大搜索、单列触控行、行尾操作、FAB、动作抽屉和 Back 回调生命周期。

`FileManagerWorkspace` 保留为唯一的文件浏览状态与 mutation 运行时。它向移动页提供 `FileManagerWorkspaceController`，只公开数据和命令，不返回页面 Widget；移动页通过 `viewBuilder` 渲染自己的布局。上传、删除、分享、重命名、回收站与目录导航因此只有一份实现，而桌面页面没有移动渲染分支。

`MobileFileManagerNavigation` 用无参 `clear()` 移除页面回调，不通过 Dart method tear-off 的相等性判断解绑。

移动 controller 另持有 bucket 列表、桶+prefix、桶回收站三种逻辑位置的栈。进入目标时先压入当前位置并递增请求 epoch，再开始远端加载；因此加载和错误态同样有左上返回，系统 Back 也先消耗文件位置而不是 `TabNavHistory`。首屏、分页和 mutation 收尾刷新共享位置+epoch 请求上下文；Back 载入旧位置会使较早请求的成功或失败失效，不能覆盖当前页面；回收站位置保留来源 prefix，返回会恢复打开它的目录。

外部「打开同步目录」由壳层分配递增 ticket。子页只有携带仍匹配 ticket 的完成或取消才能消费它，连续请求采用 latest-wins；同步尚在桶发现阶段也建立可取消的移动返回层。替换或取消仅回滚本次同步压入的历史后缀，保留用户已有的目录历史。用户主动切 tab、系统 Back 与左上返回均以最新 ticket 为准，异步 post-frame 选页不得反向夺回页面。

桌面文件页以同一递增 listing view generation 包住桶、对象、回收站首屏及两种分页，提交页面状态与 finally 的分页标记前均确认它仍是当前视图。mutation 刷新改按逻辑源位置确认(Android `_mobileLocation`、桌面 `_desktopListingResumeTarget`)，使 A→B→A 的完成可刷新新 A、B 加载/错误时的旧 A 则不可夺回页面；桌面同步 discovery 期再以开始时的 generation 截断旧刷新。对象缓存另持有失效 epoch；任何 mutation（包括超时后远端是否已生效未知的失败）推进 epoch，使已在途的旧页不能在失效后回填缓存。开始桌面同步跳转时先推进该代际并保存此前的加载快照及真实 primary target；取消或目标不存在时恢复快照，原本的桶列表、目录或回收站请求按该 target 重新发起。静默对象刷新也在 current-generation finally 释放被淘汰分页留下的 guard。

若 Android 同步目标在解析前被另一个请求替换，新请求又找不到桶，workspace 消费当前 ticket 后重新加载保存的 origin。被替换请求的迟到结果已失效，因而既不会覆盖 origin，也不会留下无执行者的 loading 状态。

写操作把“远端副作用”和“当前 UI 是否仍在源位置”分开处理：上传、创建、复制、移动、重命名、删除和回收站恢复在远端返回后先失效源 bucket 的对象缓存；只有逻辑源位置仍为同一 bucket+prefix 时才重新加载可见列表，并由这次加载捕获新的 epoch；桌面同步 discovery 期另保留原始 generation fence。这样既不让 A 目录的晚完成在 B 加载时取消 B，也不让 A→B→A 后的完成留下 A 的旧缓存。

## Alternatives considered

- **在桌面 `FileManagerPage` 内按平台切换 Widget 树** — 表面可复用状态，实则使移动 UI 依赖桌面 State 的私有字段和扩展，无法独立维护。
- **复制完整文件状态机到移动页** — 会复制上传、删除、分页、任务刷新与元数据兼容逻辑，两个客户端很容易产生语义漂移。
- **立即把 workspace 提升为独立 Dart library** — 会要求迁移现有大量 `part of 'file_manager_page.dart'` 文件，超出本次 Android 呈现改造范围；controller 已建立单向依赖边界，未来需要时可机械提升。
- **用当前 `_activeBucketEntry` 判断能否返回** — 它只在远端请求成功后才会更新，导致桶或回收站的加载/错误期把 Android Back 错交给底栏历史，也无法保留回收站的来源目录。
- **在移动页面复制异步导航状态** — 会让请求生命周期与共享 workspace 的加载状态分叉；位置栈和 epoch 归入 controller，保持一处文件操作和请求状态机。
- **用无参“已消费”回调清除同步跳转** — 较早的 A 完成可清掉 parent 中更新的 B，且用户 Back 无法撤销尚未传到子树的最新跳转；ticket 使消费与取消都可精确比对。
- **只用同步 ticket 保护桌面目标请求** — 用户既有的桶、对象、回收站或分页请求仍可能晚于新目标提交，或留下旧的分页 loading 标记；所有主列表共享 view generation 才能覆盖这些来源。
- **从桌面当前可见状态推断取消后的恢复目标** — 桶列表请求在成功前仍保留旧目录状态，推断会向错误目录重发；快照必须保存发起时的 primary target。
- **只在源 request 仍为 current 时失效 mutation 缓存** — 用户离开目录后会保留旧缓存；缓存失效是远端副作用的后处理，而可见刷新才受当前位置约束。

## Consequences

- Android 可以独立演进触控布局而不影响桌面面包屑、拖放、网格和工具栏。
- 共享工作区仍是文件操作、权限、分页和刷新状态的唯一来源，避免高风险业务逻辑分叉。
- 公开 controller 是跨页面契约；新增移动表面需求应先扩展数据/命令，而不是重新访问 workspace 私有状态。
- 当前 workspace 仍由 `file_manager_page.dart` library 承载。若 controller 继续扩张，应把它和相关 parts 提升为独立 library。
- 文件位置栈是 Android 专属导航状态，桌面面包屑、桌面回收站关闭和底栏历史的既有语义不变。
- 同步 ticket 与移动位置栈共同决定外部跳转的可见性；壳层是 ticket 的唯一消费者，workspace 不持有跨壳的导航真相。
- 桌面同步取消恢复的是此前的可见状态；若该状态为加载中，重新请求当前列表而不留下没有执行者的 spinner。
- Android 无法解析替换目标时恢复原文件位置，旧目标的迟到结果仍受 epoch 拦截。
- mutation 的源缓存总会失效，非源位置的列表和滚动状态不会被后台完成打断。

## Testing

`flutter analyze`、移动导航/偏好/行 hover 测试以及 `widget_test.dart` 覆盖桌面与移动呈现隔离、48px 搜索、FAB 动作收纳和 Android Back 的目录、左上返回（含桶/目录加载中）、加载中桶、对象/回收站分页、回收站恢复、目录 mutation 收尾刷新、删除期间打开回收站、回收站来源目录、桌面与 Android 的同步 A/B latest-wins、慢桶取消、嵌套历史取消、上传 A→B→A、tab 历史与退出顺序；`mobile_file_manager_browser_test.dart` 锁定桶行与桌面一致的 WhiteSur 存储服务器图标。
