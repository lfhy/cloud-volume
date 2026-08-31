# Agent Note: Android 应用标识迁移

Status: implemented

## Problem

Android 应用标识从 `cn.ihep.cloudvolume.remote_storage` 改为 `com.cloud.volume` 时，PackageManager 不把它视作原应用的升级。标识还决定私有 UID 和应用数据目录；若把这次改动误当作可原地升级，会让既有账号、缓存与未完成任务在新安装中不可见。

## Decision

Android 的 `namespace`、`applicationId` 与启动 Activity 包名统一使用 `com.cloud.volume`。旧包与新包作为独立应用共存，新包不尝试读取、修改或删除旧包的私有数据。

账号配置的跨包迁移使用既有远端配置备份：用户在切换前保存备份，并在新包首次启动时选择恢复。未提前备份的账号需要重新配置；缓存、任务和其它包私有运行时状态不迁移。

## Alternatives considered

- **保留旧应用标识** — 能维持原地升级，但不能满足新的公开 Android 包名要求。
- **让新包直接复制旧包私有目录** — Android 的每包 UID 与沙箱权限不允许这样读取，且任何规避方式都会破坏平台安全边界。
- **在切换时删除旧包数据** — 会造成不可恢复的数据丢失，也阻止用户保留旧包作为迁移期间的回退入口。

## Consequences

- 发布和支持材料必须明确这是新安装，而非旧 APK 的直接更新。
- 远端配置备份是账号迁移的用户主导通道；它不能替代缓存、任务或其它私有运行时状态的迁移。
- 旧包数据保持原样，用户完成新包验证后可自行决定是否卸载旧包。

## Testing

`flutter analyze` 与 Android Kotlin 编译验证新的 namespace、Activity 包名和 Manifest 的相对 Activity 引用；`go test ./...` 保持桥接配置路径的回归覆盖。
