# DOC_STANDARDS — 文档分层与预算规范

本文件是「规范文档规范」:定义每个文档归属哪一层、一条事实只能有一个家、字数预算门禁、以及防膨胀检查清单。所有新文档和文档修改必须遵守本规范。历史背景:根 `AGENTS.md` 曾增长到 1630 行 / 327KB,超出会话注入上限(约 430 行之后的内容每个新会话都看不到),2026-08-29 拆分为本结构,见 [PROJECT_GUIDE.md](PROJECT_GUIDE.md) 的迁移记录。

## 分层归属表(one home per fact)

每条事实只有一个家——放在负责它的那一层;其它地方只留链接。根 `AGENTS.md` 只放"每次会话都必须在上下文里的常备规则",每条 1–3 行并链接到归属文档。

| 层 | 职责 | 不允许出现的内容 |
|---|---|---|
| 根 `AGENTS.md` | 常备硬规则:结构上限、构建/验证/提交/评审命令、三大 binding 不变式的简述、必读入口、反膨胀规则。每条 1–3 行 + 链接 | 故事、操作过程、变更史、从链接目标复述的细节 |
| [AGENT_GUIDE.md](AGENT_GUIDE.md) | 必读顺序与工作规则(探索前先查 Code Map、探索结论必须落盘) | 具体特性的文件清单 |
| 本文件 | 文档规范本身 | 特性内容 |
| [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md) | 构建/运行/验证/提交流程的完整规则与理由 | 特性的文件清单、UI 规范 |
| [CODE_MAP.md](CODE_MAP.md) | 索引:每个特性域一行摘要 + 链接到 `features/*.md`,外加仓库布局 | 特性正文、数据流、gotcha |
| `features/*.md` | 特性正典:文件集、职责、数据流、binding 契约、gotcha。**描述现状** | 评审/修复过程叙事(→ PROJECT_GUIDE)、设计决策的理由与替代方案(→ notes) |
| `notes/{proposed,implemented,rejected}/<class>/`(见 [notes/README.md](notes/README.md)) | 决策记录(Agent Note):为什么这样设计、放弃了什么替代方案、后果与验证。格式由 `check_agent_notes.sh` 门禁 | 现状文件清单(→ features)、变更史叙事(→ PROJECT_GUIDE)、双语副本(仅中文单语) |
| [PROJECT_GUIDE.md](PROJECT_GUIDE.md) | 探索记录与历史存档:带日期的评审结论(P1/P2/P3 修复过程)、事故复盘、迁移记录。按固定格式追加,无预算上限 | 仍需每次会话看见的现行规则(应上移到正典);设计决策的理由(→ notes) |
| 设计文档(`MountMetadataJournalPlan.md`、`P2PSyncDesign.md`、`WindowsMountRegressionMatrix.md`、`AddingStorageBackends.md`) | 既有的专题设计/操作指南,保持原位 | 与 features/*.md 重复的正典内容(互相链接,不复制) |

## 写作规则

- **写现状,不写变更史。** 正典文档(`features/*.md`、`CODE_MAP.md`、`DEVELOPMENT_GUIDE.md`)禁用「之前/现在不再/fixed on …/2026-XX-XX 修复」式**叙事**;直接陈述当前机制。两条例外:日期本身承载信息的**证据引用**允许保留(如「实测 2026-08-01:默认 dialer = 75.011s」「v1.2.0 无桌面工件」这类复现数据/回归锚点);「不要退回 X」的 gotcha 允许保留,因为约束本身是现状,但过程细节去掉,完整过程放 PROJECT_GUIDE 记录。
- **一条事实一个家。** 同一规则出现在两处时,保留归属文档,其余改成一行链接。grep 一个特征短语就能发现重复。
- **评审结论的归档方式:** 子代理评审产生的 P2/P3 发现与修复,在对应 `features/*.md` 的「Known P2/P3」小节保留一行指针(发现 + 状态)。完整叙事按性质分流:**改变了设计决策(采纳了某方案、放弃了某替代)**的写成一条 Agent Note(格式见 [notes/README.md](notes/README.md));纯过程叙事(修复批次经过、事故时间线)追加到 PROJECT_GUIDE 的带日期记录。P0/P1 是 blocking,修复后其不变式应并入正典正文。
- **跨文档引用使用相对 Markdown 路径**(如 `[CODE_MAP.md](CODE_MAP.md)`、`[ui_rules](features/ui_rules.md)`),不要裸文件名,便于校验与跳转。
- **语言:** 正文中文为主,文件路径/代码标识符保留英文原文;新条目风格与既有条目保持一致。
- **新增特性时:**在对应 `features/*.md` 落盘(没有就新建,并加入 CODE_MAP 索引和预算清单),不要往根 `AGENTS.md` 加内容。

## 字数预算(硬门禁)

`make check-docs`(`scripts/check_doc_budgets.sh`)按字符数(`wc -m`)校验下表,超限即失败。清单里列出的文件必须存在。预算是护栏不是压缩目标;改动让文件逼近上限时保持至少 5% 余量。

超限时的处理顺序:

1. **搬走**——内容属于另一层,留一行链接;
2. **压缩**——内容属于这里但可以更短;
3. **提上限**——只有内容确实需要这个空间时才允许,并在提交说明里给出理由。反向(降上限)只在文档确有余量时进行。

| 文件 | 上限(字符) |
|---|---|
| `AGENTS.md`(根) | 14,000 |
| `docs/AGENT_GUIDE.md` | 8,000 |
| `docs/DOC_STANDARDS.md` | 14,000 |
| `docs/DEVELOPMENT_GUIDE.md` | 16,000 |
| `docs/CODE_MAP.md` | 30,000 |
| `docs/README.md` | 6,000 |
| `docs/notes/README.md` | 12,000 |
| `docs/notes/*/*/*.md`(每条笔记) | 8,000 |
| `docs/features/*.md`(每个) | 60,000 |

`PROJECT_GUIDE.md` 是无上限存档,但每条记录必须是自包含的带日期条目,不允许变成正典规则的副本。

## 防膨胀检查清单(slop checklist)

写完/改完任何文档后自查;`make check-docs` 挡不住这些,只能靠评审:

- 同一规则出现在多个家(grep 特征短语;留一个家,其余改链接)。
- 变更史叙事:「之前/now/no longer/2026-XX-XX 修复/PR #N」出现在正典文档(改写成现状;过程移 PROJECT_GUIDE)。
- 段落墙:一段话承载多条规则和括号插叙(拆分或降级到归属层)。
- 强调通胀:到处加粗/CAPS/「必须」意味着什么都不突出。
- 状态标注腐烂:「已实现!/future: …」这类实现状态会过时;正典只写机制本身(笔记的 `proposed/`/`implemented/` 目录本身就是状态,由 lifecycle 承载)。
- implemented 笔记里出现 spec-speak(`## Proposal`/`## Plan`/`## Migration plan`/`## Acceptance criteria`):已落地的决策写现在时 `## Decision`;格式门禁会拒绝。
- 把本该进 `features/*.md` 的内容写进根 `AGENTS.md`(反膨胀规则:根文件只进不出,新内容一律进 docs/)。
