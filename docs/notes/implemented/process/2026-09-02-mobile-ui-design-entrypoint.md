# Agent Note: 移动 UI 设计入口与前置阅读

Status: implemented

## Problem

移动端的导航、触控、抽屉、安全区和系统栏规则分别散落在应用壳、模态和通用 UI 文档中。开发前没有一个明确入口，容易沿用桌面交互、忽略 48dp 触控或在横屏安全区中引入裁切。

## Decision

`docs/features/mobile_ui.md` 是 Android/移动端 UI 的跨特性设计检查清单，根 `AGENTS.md` 要求在修改移动页面、导航、列表、触控或抽屉前阅读它。该页只持有跨特性原则、检查项和正典链接；组件实现、文件职责和精确技术契约仍分别由 `app_shell`、`ui_rules`、`app_modal` 与 `android_dev` 持有。

## Alternatives considered

- **把所有移动规则展开到根 `AGENTS.md`** — 每个会话都会注入这份文件，会违背其常备入口和 1–3 行规则的预算；只保留一条必读链接。
- **把全部规则迁移到一份新文档** — 会剥离现有特性文档对代码、数据流和模态契约的所有权，并制造重复正典；新页只负责跨特性设计汇总。
- **仅依赖外部移动设计 skill** — skill 不会向仓库维护者展示项目特有的 Android Back、系统栏、底栏与抽屉约束；仓库内正典必须独立可查。

## Consequences

- 移动 UI 改动有统一的预检入口，仍可沿链接进入拥有细节的特性文档。
- 新的移动设计规则先放入 `mobile_ui`；若规则属于单个组件或运行时契约，则放回该组件的 feature 文档，并从 `mobile_ui` 链接。
- 根 `AGENTS.md` 保持简短，文档索引和 Code Map 列出新的正典。

## Testing

`make check-docs` 校验文档预算、索引和 Agent Note 格式；`git diff --check` 校验 Markdown 改动无空白错误。
