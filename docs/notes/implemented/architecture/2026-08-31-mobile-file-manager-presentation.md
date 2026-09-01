# Agent Note: Android 文件管理以桌面 UX 为准

Status: implemented

## Problem

Android 文件页曾以大搜索、单列触控行、FAB 和动作抽屉重写桌面工作流。它虽然复用加载和 mutation，却让相同功能在标题、搜索、操作入口、列表密度和可用视图模式上出现两份 UX；桌面端改动无法自然传递到移动端。

## Decision

桌面文件管理 UI 是唯一的呈现正典。`FileManagerPage` 和 Android 的无状态入口 `MobileFileManagerPage` 都装配同一个 `FileManagerWorkspace`，后者通过 `file_manager_page_presentation.dart` 渲染标题、面包屑、搜索、操作栏以及 bucket、对象和回收站浏览器。Android 不维护第二套 chrome、列表、搜索或动作面板。

平台差异只留给输入与系统边界：桌面/Web 才包裹原生拖放和 file URI 剪贴板；Android 加安全区和紧凑 padding，以长按或紧凑对象行尾 `…` 打开同一份上下文菜单。桌面保留列表/网格切换和挂载操作；Android 固定列表模式并隐藏网格/列表切换、挂载、卸载和打开挂载目录入口，避免把桌面专属能力伪装成移动操作。进入桶、目录或桶回收站后二级顶栏显示返回按钮，按钮与系统 Back 共用位置栈并覆盖加载/错误状态。

`FileManagerWorkspace` 直接绑定 `MobileFileManagerNavigation` 的系统 Back 回调，并在销毁或导航实例替换时 `clear()`，不再经允许自建视图的 controller 暴露文件管理状态。Android 的 bucket 列表、桶+prefix、桶回收站位置栈仍在 workspace 内：目标在请求前提交，加载或错误状态也优先消耗 Back；同步跳转和列表请求继续使用 ticket、epoch 与 listing generation 丢弃迟到结果。

## Alternatives considered

- **保留独立触控页面** — 它有自己的视觉结构与操作分组，长期必然继续偏离桌面 UX，已删除。
- **在 Android 复制桌面 widget 树** — 代码文字相似却会让两个构建路径独立演进；改为同一 `FileManagerWorkspace` 直接产生同一组件树。
- **为触摸保留 FAB 或动作抽屉** — 这会改变桌面已建立的操作优先级；触摸需求只通过共享菜单的长按和行尾入口补足。
- **取消 Android 的文件位置栈以完全等同桌面** — 系统 Back 会过早退到 tab 或退出应用；该导航语义不改变视觉 UX，继续保留。
- **在 Android 保留桌面视图切换和挂载入口** — 这些能力依赖桌面窗口/文件系统边界，移动端没有对应工作流；固定列表并隐藏入口可以保持组件树一致而不暴露不可用动作。

## Consequences

- 文件管理 UX 的每次视觉或交互变更默认同时覆盖桌面和 Android；平台能力差异通过同一组件树的条件入口表达。
- Android 专用代码只能处理系统 Back、安全区和触摸触发，不得新增另一套文件浏览器或动作容器。
- Android 文件位置栈、同步 ticket 和 listing generation 继续隔离异步导航，不影响桌面面包屑和鼠标工作流。
- `FileManagerWorkspace` 仍由 `file_manager_page.dart` library 承载；需要跨 feature 复用时再整体提升为独立 library。

## Testing

`test/widget_test.dart` 同时断言 Android 出现 `FileManagerActionBar`、`FileManagerBreadcrumbBar` 和共享 bucket / 对象 / 回收站浏览器，并锁定 Android 无视图切换、无挂载入口、列表模式以及已加载/加载中二级页的顶栏 Back；同时覆盖 Android 文件 Back、同步跳转、分页和 mutation 的迟到响应。`flutter analyze` 与完整 Go / Flutter 测试集验证共享呈现和既有文件操作。
