# 云卷(Cloud Volume)文档索引

本目录是仓库文档的正典归属;根 `AGENTS.md` 只保留常备规则入口。文档分层、写作规则与字数预算见 [DOC_STANDARDS.md](DOC_STANDARDS.md)。

## 协作与规范

- [AGENT_GUIDE.md](AGENT_GUIDE.md) — 必读顺序与工作规则(动手前先读)。
- [DOC_STANDARDS.md](DOC_STANDARDS.md) — 文档分层规范(one home per fact)、预算门禁、防膨胀清单。
- [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md) — 构建、验证、提交与提交前评审流程。
- [CODE_MAP.md](CODE_MAP.md) — 特性域索引(一行摘要 + 链接到 `features/*.md`)。
- [PROJECT_GUIDE.md](PROJECT_GUIDE.md) — 探索记录与历史评审结论存档(带日期,无预算上限)。

## 特性正典(features/)

挂载与元数据核心:[mount_metadata_core](features/mount_metadata_core.md) · [remote_tasks](features/remote_tasks.md) · [mount_queues_legacy](features/mount_queues_legacy.md) · [macos_webdav_mount](features/macos_webdav_mount.md) · [mount_external_sync](features/mount_external_sync.md)

账号与文件管理:[account_management](features/account_management.md) · [file_actions](features/file_actions.md) · [file_sync_p2p](features/file_sync_p2p.md)

桌面应用壳与 UI:[app_shell](features/app_shell.md) · [ui_rules](features/ui_rules.md) · [app_modal](features/app_modal.md) · [settings](features/settings.md)

平台:[windows_platform](features/windows_platform.md) · [windows_dev](features/windows_dev.md) · [android_dev](features/android_dev.md)

后端:[storage_backends](features/storage_backends.md)

## 专题设计文档

- [AddingStorageBackends.md](AddingStorageBackends.md) — 新增存储后端的五层改动指南。
- [MountMetadataJournalPlan.md](MountMetadataJournalPlan.md) — 统一元数据架构的设计、耦合审计与分期 TODO。
- [P2PSyncDesign.md](P2PSyncDesign.md) — 跨客户端变更发现的 P2P 分期设计。
- [WindowsMountRegressionMatrix.md](WindowsMountRegressionMatrix.md) — Windows 挂载回归矩阵。
