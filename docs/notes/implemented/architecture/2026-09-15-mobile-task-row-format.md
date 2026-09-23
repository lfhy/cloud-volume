# Agent Note: 任务行格式与文件/回收站行统一

Status: implemented

## Problem

用户指出任务队列页的列表行与文件管理/回收站页不匹配。逐项对照 `FileListTile`(文件/回收站行的正典)后有三处分叉:行分隔线是 80px 缩进的 `Divider(height:1, alpha 0.45)`(正典是全宽底部发丝线 border 0.55/0.6);标题字重 w600(正典 w500);Android 行尾在 `…` 之外还有一个「查看明细」chevron(正典行尾仅一个 `…`)。

## Decision

1. **分隔线**:行容器 `AnimatedContainer` 的 `decoration.border` 改为 FileListTile 同规格的全宽底部发丝线(0.55/0.6),并同其调用方惯例**末行不画**(除非后面还有历史分页行)——`transfers_page_remote.dart` 的分组循环改为索引遍历计算 `showDivider`。
2. **80px 契约收窄**:`remoteTaskContentIndent`(80)从「标题列+明细面板+行分隔线」三元对齐收为「标题列+明细面板」二元对齐(分隔线退出该契约,remote_tasks.md 已同步)。
3. **行尾**:Android 明细 chevron 移除,「查看明细/收起明细」由 `_OverflowMenuButton` 在打开抽屉时按最新展开态拼为**首项**;批量抽屉同样携带(Android 选中态行点击是切换选择,选中行没有其他明细入口)。桌面保留内联图标+chevron。
4. **标题字重** w600→w500(两密度,对齐 FileListTile)。
5. **批处理运行中**:`RemoteTaskOverflow` 增加 `enabled`,运行中行 `…` 整体禁用(否则会打开只剩明细的空标题抽屉——评审发现的回归)。

## Alternatives considered

- **保留 chevron、只统一分隔线/字重** — 行尾仍是两个按钮,与正典单 `…` 不符;明细作为抽屉动作与其他行级动作同层,交互一致。
- **明细抽屉动作仅行级分支** — 选中态下该行点击是切换选择,没有其他明细入口,批量抽屉不携则会锁死;按偏差记录(doc 已注明)。
- **分隔线保持 80px 缩进、仅改线规格** — 仍是"文件行全宽、任务行缩进"的可见分叉;明细面板继续 80px 缩进即可保持标题对齐。
- **busy 时打开空抽屉** — 评审指出这是可触达回归;禁用(参考回收站忙行)更一致。

## Consequences

- 三页列表行(文件/对象、回收站、任务)在 Android 的分隔线、字重、行尾形态一致;任务行保留 kind 色卡、状态徽标、活动 spinner(正典允许的行内 chrome)与 14 字符截断预算(最窄行,既有正典)。
- 分隔线全宽变更是两平台共享的视觉变更:桌面任务列表卡片内的行分隔线同样变为全宽发丝线、末行不画——与桌面文件/回收站卡片内的行规格一致,属"与 FileListTile 统一"的本意。
- `_toggleExpanded` 加 mounted 守卫(抽屉动作闭包可能比行存活更久)。
- 批量运行中行 `…` 禁用(无 spinner,页面级入口已有全局 spinner)。

## Verification

- `flutter analyze` 干净(仅 2 条既有 deprecation info);`flutter test` 全量通过。
- transfers「android row overflow owns selection actions」钉住:行内无 chevron(行作用域)、明细展开/收起经抽屉往返、批量抽屉同携「查看明细」;desktop 用例继续钉内联图标与「共 N 项」表面。
