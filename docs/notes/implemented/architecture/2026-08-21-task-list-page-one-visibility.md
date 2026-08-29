# Agent Note: 任务列表"未决优先"排序与首页可见性契约

Status: implemented

## Problem

任务列表按时间倒序分页(offset 分页),积累的终态历史会把进行中任务挤出第一页。2026-08-21 实际观察到 558 个 done 任务组把新任务推到 `limit=100` 之后:文件管理页依赖"metadata 任务 active→终态时强制刷新列表"这一联动,首页看不到活跃任务意味着联动静默失效——同步完成的文件在页面上不出现,且没有任何报错。

## Decision

排序、分页与轮询职责拆开,契约对桌面桥接与 Web API 一致(全文见 [remote_tasks](../../../features/remote_tasks.md)):

- 排序:未决状态(`pending/waiting/blocked/retry_wait/running/verifying/cancel_requested/reconciling/failed/conflict`)先于终态历史;组内最新在前;ID 决胜。**偏移分页在该排序之后应用**。
- 轮询:`RemoteTaskStore.pollActive` 用 `includeHistory: false`,活跃任务永远在第一页;响应只过滤行,计数(`total`/队列数)仍按全范围计算。历史只经页面进入时的 `loadInitialHistory`(首个 100 行)与用户显式 `loadMore`(`_RemoteHistoryPager` 是列表最后一行)。
- 排序 key 必须解析时间戳(`time.Parse` RFC3339Nano/RFC3339)而非比较 wire 字符串:运行时快照(本地时区)与 metadata 任务(UTC)才能正确交错。
- WebSocket 推送只做"有变化"的 tick 触发一次 active-only 轮询;轮询(700ms 活跃/2s 空闲)永远是正确性回退。

## Alternatives considered

- **WebSocket 流式推送全部任务(含历史)** — 把无界终态流塞进推送通道,服务端与客户端都要处理背压/去重;而历史本身没有实时性需求,显式分页更简单。
- **调大 `limit` 或让页面翻页找活跃任务** — 治标:历史无限增长,任何固定 limit 都会被超过,且联动失效的根因(活跃任务不在第一页)没变。
- **wire 字符串直接比较时间戳** — 实现最省,但本地时区 `createdAt` 与 UTC RFC3339Nano 混排时错序,且不同来源格式演进时脆弱。

## Consequences

- 回归被钉死:`bridge/remote_task_ordering_test.go` 固定 118 done + 2 active → 第一页含两个活跃任务;`remote_task_visibility_test.go` 钉住"计数含历史、行只过滤活跃"的分离。
- 复杂度转移:active-only 计数与行可见性分离带来 `queue.reported`/`page.hasTotal` 存在标志、历史增长时的 cursor 版本化失效(`_historyCursorVersion`)、history-only 队列的分页可达性(`showHistoryPager` 早退)——这些细节都有测试,但后来者必须理解这套契约才能改任务列表。
- 任何排序/分页改动必须配"活跃任务留在第一页"的回归测试,这条已升格为根 `AGENTS.md` 的三大 binding 不变式之一。
