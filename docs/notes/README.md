# Agent Notes — 决策记录

一种文档只放这里:**Agent Note 记录一条影响本仓库的决策或提案——*为什么*这样做、放弃了什么替代方案、后果与验证方式**。代码和 `features/*.md` 承载"是什么"(文件、数据流、gotcha);代码承载不了的"为什么"归这里。本文件定义笔记放哪、何时写、以及文件内格式;`scripts/check_agent_notes.sh`(挂在 `make check-docs`)强制执行格式。

本目录**只有中文单语**:不建 `.zh.md` 副本、不建 i18n sidecar——双语配对体系被有意排除(见 [文档分层决策记录](implemented/process/2026-08-29-layered-docs-and-budget-gate.md))。

## 目录与命名

每条笔记两个编码轴,都编进路径:`{lifecycle}/{class}/yyyy-mm-dd-主题.md`:

- **Lifecycle**(顶层目录)= 笔记状态,状态变化时文件在目录间移动:
  - **`proposed/`** — 实现前评审的提案,尚未构建(或只建了一部分)。
  - **`implemented/`** — 决策已落地。文件记录决定了什么、拒绝了什么,并**与实际发布保持同步**:代码之后移动文件、改名、改 key/默认值时,同一变更集内更新笔记中的事实(只改事实——路径、名称、结构——不改决策本身)。
  - **`rejected/`** — 提案被考虑后否决。只在它的理由还能阻止一个有诱惑力的真实错误时保留;否则删除整个文件。
- **Class**(嵌套目录)= 决策的*种类*(封闭集合,格式门禁会拒绝集合外的目录):

| Class | 覆盖 |
|---|---|
| `feature` | 新的用户可见能力。 |
| `bug-fix` | 修正缺陷或填补事故暴露的缺口。 |
| `simplification` | 移除代码、行为或表面积而不加能力。 |
| `architecture` | 关于**发布源码**的结构决策——模块如何关联、运行时词汇是什么。 |
| `process` | 代码**周围**的工具、政策、工作流——门禁、包管理、vendoring——不是运行时行为。 |
| `testing` | 测试基础设施与策略。 |

(`architecture`/`process` 分界:前者关于我们发布的源码,后者是周边工具与工作流;`refactor` 刻意缺席——它与 `simplification` 重叠。)

文件名日期 = 该主题**首次提出**的日期(按 git 历史)。笔记之间用相对 markdown 链接互引,不用裸文件名或编号,目录间移动后链接仍有效(机械链接校验暂未接入,移动/合并/删除笔记时人工修复入链)。**不建集中索引**——lifecycle/class 目录树本身就是工作清单;低未来价值的 implemented 笔记直接删除或并入现行持有者(见下)。

## 何时写

**每个非平凡变更必须在同一变更集中新增或更新至少一条 Agent Note。** 非平凡 = 改动行为、架构、跨文件/包契约、流程或工具、测试策略、磁盘/wire/配置格式,或任何维护者可能合理重审的决策。更新已持有该决策的现有笔记即满足规则,**不要建重复笔记**。仅纯机械/局部、不改行为契约流程理由的编辑豁免。

- 未来大工作的提案从 `proposed/` 开始;已做的决定直接进 `implemented/`。
- **一条笔记绝不改写成另一条决策**:要推翻就新写一条并互相链接;被完全取代的旧笔记可并入新持有者后删除——删除前必须保留旧笔记全部独有理由、替代方案、后果、验证方式与命名缺口,并修复所有入链。
- 与其它层的关系:探索结论(结构/文件/数据流)写 `features/*.md`;带日期的过程叙事(评审批次、事故复盘)写 [PROJECT_GUIDE](../PROJECT_GUIDE.md);**决策理由写这里**,features 里只留一行链接。

## 文件格式

每条笔记开头两行精确为:

```markdown
# Agent Note: <标题>

Status: <status>
```

`Status:` 取三种形式之一,且必须与所在 lifecycle 目录一致(门禁交叉检查;机器 token 保持英文原文以便校验):

- `Status: proposed`
- `Status: implemented`
- `Status: rejected — <一句话理由>`(拒绝理由是唯一带内容的 status——它是读者来看的事实)

status 不带日期不加括号:文件名持有首次提出日期,其余归 git;"以修订形式接受"这类信息写进正文。

### 正文骨架

正文必须以 `## Problem` 开头——动机,须脱离解决方案独立成立。其后按 lifecycle:

**`proposed/`:**

```markdown
## Problem
## Proposal
…自由的技术小节…
## Alternatives considered
## Acceptance criteria
## Risks
```

`## Proposal` 是意图中的改动,可以用将来时;`## Acceptance criteria` 说清什么可观察状态算完成;`## Risks` 同时覆盖可能出的问题与该改动有意放弃的东西。

**`implemented/`:**

```markdown
## Problem
## Decision
…自由的技术小节…
## Alternatives considered
## Consequences
```

`## Decision` 用**现在时**描述已发布的现实,整个文件随它保持同步。提案式小节标题在这里是 spec-speak,门禁拒绝:`## Proposal`、`## Plan`、`## Migration plan`、`## Acceptance criteria` 不得出现在 implemented 笔记中。陈述现在时事实的 `## Testing`、`## Deferred`、`## Related` 小节允许。

**`rejected/`:**

提案原样冻结:保留提案期小节(含 `## Acceptance criteria`/`## Plan`),结论在 `Status:` 行。只强制 header 块、`## Problem` 开头、`## Proposal` 与下方的 Alternatives 义务。

### Alternatives considered — 强制

每条笔记都有 `## Alternatives considered`:每个真实替代方案及它输掉的原因,一个加粗引导的段落一个方案,或每个有争议的方案一个 `### 为什么不是 <X>?` 小节。**没记录它击败了什么的决策会招来反复重审——这正是 Agent Notes 要阻止的失败。** 替代方案要如实记录,不许事后编造;确不可考的早期决策注明即可。

### 生命周期之间移动

把文件移到另一个 lifecycle 目录 = 同一变更集内更新 `Status:` 行并重写为该目录的骨架:`proposed → implemented` 把 `## Proposal` 改写为现在时 `## Decision`,`## Acceptance criteria`/`## Risks` 折进 `## Consequences`(或现在时的 `## Testing`/`## Verification`),丢弃计划只留落地结果;`proposed → rejected` 只在 `Status:` 行加理由并冻结。
