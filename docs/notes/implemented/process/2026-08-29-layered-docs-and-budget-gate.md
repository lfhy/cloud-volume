# Agent Note: 分层文档体系与字数预算门禁取代单文件 AGENTS.md

Status: implemented

## Problem

根 `AGENTS.md` 同时承载常备规则与 34 条 Code Map 特性条目,增长到 1630 行 / 327KB 后超出会话注入上限:约 430 行之后的内容(20+ 个特性条目)对每个新会话不可见。也就是说,文件后半部的知识——WinFsp、文件同步、自动更新、FTP/SFTP 等——已经事实上失效,尽管维护规则仍要求持续更新它。没有机制阻止它再次膨胀。

## Decision

文档按"一条事实一个家"分层,根文件只保留常备命令,并用机器门禁防再膨胀:

- 根 `AGENTS.md`(57 行):每次会话都必须看见的硬规则,每条 1–3 行 + 链接;开头即反膨胀规则——新内容一律进 `docs/`,不扩充本文件。
- `docs/` 正典层:[AGENT_GUIDE](../../../AGENT_GUIDE.md)(必读顺序)、[DOC_STANDARDS](../../../DOC_STANDARDS.md)(分层归属表 + 写作规则 + slop 清单)、[DEVELOPMENT_GUIDE](../../../DEVELOPMENT_GUIDE.md)(构建/验证/提交/评审)、[CODE_MAP](../../../CODE_MAP.md)(索引)。
- `docs/features/*.md`:16 个特性正典(文件集、数据流、binding 契约、gotcha),描述**现状**。
- `docs/PROJECT_GUIDE.md`:带日期的过程存档(评审批次叙事、事故复盘、迁移记录),无预算上限。
- `scripts/check_doc_budgets.sh` + `make check-docs`:按字符数(`wc -m`)门禁——根 14k、features 每个 60k、PROJECT_GUIDE 豁免;超限处理顺序 搬走→压缩→提上限(提上限须在提交说明给理由)。

写作纪律:正典文档写现状不写变更史("fixed on …" 式叙事进 PROJECT_GUIDE);日期本身承载信息的证据引用(复现数据、回归锚点)例外。

## Alternatives considered

- **继续养大单文件 AGENTS.md** — 输在注入上限是硬约束:内容再多也到不了会话,维护投入白费。
- **完整照搬 coding 仓库的 tier 体系(含双语配对、生成目录、链接校验、doc-sync 门禁)** — 它的纪律值得学,但双语 sidecar 与 hash 配对门禁是为多人开源仓库设计的;本仓库单人开发、中文为主,双倍维护成本买不到对等收益。取其分层归属表、预算门禁、slop 清单,弃其 i18n 机制。
- **只拆目录不加门禁** — 拆分只解决"太大",不解决"再膨胀":没有预算红线,`features/*.md` 或 CODE_MAP 会成为下一个 327KB。门禁必须机械(sh 脚本 + make 目标),不能靠自觉。

## Consequences

- 每个新会话只为根文件付 57 行上下文成本;深层内容按需经链接读取,且全部可达(不再有注入截断盲区)。
- 完整性可校验:迁移时用脚本比对旧文件全部 684 个反引号文件引用,只有 3 个"已删除文件"的历史注记被有意舍弃。
- 代价:规则现在分散在多层,新贡献者/新会话必须走 AGENT_GUIDE 的必读顺序才能找对家;预算表需要随文档演进维护,提上限要给理由。
- 评审结论的落点变复杂了一档:P2/P3 一行指针留 feature 文档,完整叙事进 PROJECT_GUIDE,改变设计决策的写成 [Agent Note](../../README.md)(本笔记体系同日引入)。
