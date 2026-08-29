# Agent Guide — 必读顺序与工作规则

动手之前(探索、搜索、修改、构建、测试)按顺序读:

1. [文档索引](README.md) — 定位任务相关材料。
2. [CODE_MAP.md](CODE_MAP.md) — 找到受影响的特性域,进入对应 `features/*.md`。
3. [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md) — 构建/验证/提交/评审要求。
4. 相关专题文档:`AddingStorageBackends.md`(新存储后端五层改动)、`MountMetadataJournalPlan.md`、`P2PSyncDesign.md`、`WindowsMountRegressionMatrix.md`。
5. 开始新的调查前,先查 [PROJECT_GUIDE.md](PROJECT_GUIDE.md) 是否已有结论,不要重复已记录过的探索。

## 工作规则

- **探索结论必须落盘(binding):** 任何为回答问题/调试/理解特性而做的探索——即使没有代码改动——在回合结束前把可复用的结论写进对应 `features/*.md`(正典)或 PROJECT_GUIDE 记录(历史)。目标是下一个会话不用重读同样的文件。
- **特性正典同步(binding):** 每次新增特性或特性文件集变化,在同一变更集(提交前)更新对应 `features/*.md`:参与文件、职责、数据流。新特性域新建文件并加入 CODE_MAP 与预算清单。
- **文档分层与预算遵守 [DOC_STANDARDS.md](DOC_STANDARDS.md):** 一条事实一个家;正典写现状;`make check-docs` 必须通过;不要往根 `AGENTS.md` 加内容。
- 保留用户已有的未提交改动;一次改动聚焦一个主题;不提交构建产物。
- 完成实现并通过验证后自动创建常规(非 amended)提交,提交说明用简洁中文;只暂存本任务相关文件。
- 落地 `main` 前必须通过 P0/P1 级子代理评审,流程见 [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md)。
- `lib`、`go`、`bridge`、`macos/Runner` 下的手写代码文件不超过 500 行且至少一条有意义注释;拆分与组织细则见根 `AGENTS.md` 与 [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md)。
- UI 改动(hover、loading、设置卡、模态框)动手前必读对应 binding:[ui_rules](features/ui_rules.md)、[app_modal](features/app_modal.md)。
