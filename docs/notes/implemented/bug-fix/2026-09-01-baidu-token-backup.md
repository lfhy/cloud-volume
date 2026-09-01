# Agent Note: 百度网盘 OAuth 刷新必须推进配置备份

Status: implemented

## Problem

百度网盘请求遇到过期凭证时,存储层会自动刷新 OAuth token 并直接写回 profile。该写入绕过 bridge 原本只覆盖用户操作的自动备份队列,因此开启配置备份的用户仍可能在远端快照中保留旧 token。若刷新恰好发生在上传期间,单纯补一个入口还会被进行中的队列标志吞掉;但防抖等待期间的写入仍必须合并到首轮快照,不能误触发重复上传。

## Decision

配置层在 profile 成功写入后调用进程级 mutation hook,由 bridge 注册为 `queueAutomaticConfigBackup`。这样后台 token 刷新与普通 profile 保存共享同一 2 秒合并窗口,storage 包不依赖 configbackup 或 bridge;bridge 不再为这两类保存重复入队。自动备份队列只在实际上传阶段记录是否又发生写入;上传结束后若有写入则再排一轮,确保快照在 token 刷新后重新导出,而防抖等待期间的写入不会产生重复快照。

## Alternatives considered

**只在百度存储层直接调用备份包** — 会让 storage 反向依赖 configbackup,并把远端备份失败耦合到每次数据请求;同时无法覆盖其它绕过 bridge 的配置写入。

**只在百度刷新后立即同步上传** — 会破坏现有合并窗口,在高并发请求下产生大量快照,且刷新发生在已有上传期间时仍可能上传旧归档。

## Consequences

profile 写入成功且释放 `config.db` lease 后会触发一个轻量进程级通知;未注册 observer 的纯 config 使用者行为不变。自动备份仍是 best-effort,每轮上传结束后若期间发生 token 刷新便追加一轮合并备份。`go/config/mutation_hooks_test.go` 覆盖成功写入通知与失败写入不通知;`bridge/dispatch_config_backup_test.go` 锁定防抖窗口合并与上传中写入补跑。`go test ./go/config ./go/storage` 与 `go test ./bridge` 验证通过。
