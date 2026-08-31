# Agent Note: Android 文件管理的独立呈现层

Status: implemented

## Problem

桌面文件管理页以面包屑、密集操作栏、列表/网格切换、鼠标输入和桌面拖放为中心。把这套结构压缩到 Android 会挤占内容与搜索空间，也会令后续移动交互改动必须穿过桌面页面的私有状态。用户要求 Android 页面与桌面页面分开并单独维护，同时文件加载、上传、删除和回收站等语义仍必须一致。

## Decision

`FileManagerPage` 是桌面入口，`MobileFileManagerPage` 是 Android 专属 Stateful 页面。移动页自有 `MobileFileManagerSurface`、`MobileFileManagerBrowser` 与 `mobile_file_manager_actions.dart`，负责大搜索、单列触控行、行尾操作、FAB、动作抽屉和 Back 回调生命周期。

`FileManagerWorkspace` 保留为唯一的文件浏览状态与 mutation 运行时。它向移动页提供 `FileManagerWorkspaceController`，只公开数据和命令，不返回页面 Widget；移动页通过 `viewBuilder` 渲染自己的布局。上传、删除、分享、重命名、回收站与目录导航因此只有一份实现，而桌面页面没有移动渲染分支。

`MobileFileManagerNavigation` 用无参 `clear()` 移除页面回调，不通过 Dart method tear-off 的相等性判断解绑。

## Alternatives considered

- **在桌面 `FileManagerPage` 内按平台切换 Widget 树** — 表面可复用状态，实则使移动 UI 依赖桌面 State 的私有字段和扩展，无法独立维护。
- **复制完整文件状态机到移动页** — 会复制上传、删除、分页、任务刷新与元数据兼容逻辑，两个客户端很容易产生语义漂移。
- **立即把 workspace 提升为独立 Dart library** — 会要求迁移现有大量 `part of 'file_manager_page.dart'` 文件，超出本次 Android 呈现改造范围；controller 已建立单向依赖边界，未来需要时可机械提升。

## Consequences

- Android 可以独立演进触控布局而不影响桌面面包屑、拖放、网格和工具栏。
- 共享工作区仍是文件操作、权限、分页和刷新状态的唯一来源，避免高风险业务逻辑分叉。
- 公开 controller 是跨页面契约；新增移动表面需求应先扩展数据/命令，而不是重新访问 workspace 私有状态。
- 当前 workspace 仍由 `file_manager_page.dart` library 承载。若 controller 继续扩张，应把它和相关 parts 提升为独立 library。

## Testing

`flutter analyze`、移动导航/偏好/行 hover 测试以及 `widget_test.dart` 覆盖桌面与移动呈现隔离、48px 搜索、FAB 动作收纳和 Android Back 的目录、回收站、tab 历史与退出顺序。
