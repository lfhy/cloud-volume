# Agent Note: Android 配置库使用单一进程句柄

Status: implemented

## Problem

Flutter 通过 `Isolate.run` 并发执行 FFI 调用，而配置读写原本会为每次调用独立打开并关闭 `config.db`。Android 版 bbolt 使用属于进程的 `fcntl(F_SETLK)` 锁，故同一进程内的多个文件描述符不能由该锁彼此隔离；各句柄会并发维护自己的 freelist。还原配置备份的写事务由此可触发 `page already freed` 并终止进程。

事后 `bbolt check` 可验证落盘文件仍然一致。这一区分很重要：故障位于并发句柄的内存 freelist 视图，并不说明备份内容损坏，也不说明 `DeleteBucket` 或 `CreateBucket` 的单一事务不安全。

## Decision

`go/config/config_db_shared.go` 为当前应用数据根目录持有唯一 bbolt 句柄。所有运行时配置 API 通过 `acquireConfigDB` 获得该句柄及一次性 lease 释放函数，业务调用完成后才释放。切换移动端应用数据根目录会等待现有 lease 清空、关闭旧句柄、更新根目录，再允许新调用打开新库；同一路径的重复设置不触发切换。

## Alternatives considered

- **只在 Flutter 或 bridge 层串行化还原调用** — 配置库还会被自动备份、轮询、缓存索引和其它 Go 调用访问；在入口逐一维持串行化清单会漏掉未来调用，也不能保证进程内只有一个 bbolt 句柄。
- **升级 bbolt 版本** — 当前与候选版本在 Android 上仍使用 `fcntl(F_SETLK)`；升级本身没有改变同进程多句柄的锁语义。
- **避免还原时删除并重建 profiles bucket** — 该事务在单一健康句柄下是原子且有效的还原语义，绕开它只隐藏并发缺陷，并会扩大数据迁移和回滚的行为改动。
- **继续每次打开后立刻关闭数据库** — 这在依赖文件锁可靠隔离的环境看似简单，但 Android 的进程关联锁不提供该保证，并且关闭一个描述符还会影响该进程的锁状态。

## Consequences

配置操作共享 bbolt 原生的并发读写协调，进程存活期间保留一个打开文件描述符。移动端首次改变数据根目录时会等待短暂的正在执行配置调用；常规重复连接到同一私有目录不会产生等待。落盘库的完整性检查仍保留为诊断手段，但不再把它误当成并发句柄安全的证明。

## Testing

`go/config/config_db_shared_test.go` 覆盖共享句柄、同根目录无中断、异根目录等待 lease、重复 `RestoreConfigBackup`、与并发轮询读取交错的还原，以及最终 `tx.Check()`。`go test -race ./go/config -run 'Test(ConfigDB|RestoreConfigBackup)' -count=1` 验证了 registry 的并发访问。
