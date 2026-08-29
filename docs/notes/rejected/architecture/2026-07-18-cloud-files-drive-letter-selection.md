# Agent Note: Cloud Files 挂载的盘符选择

Status: rejected — `subst` 映射只是宿主目录别名,Explorer 显示宿主卷容量,多桶挂载下误导用户;承载真实容量的卷必须用 WinFsp

## Problem

Windows Cloud Files 挂载呈现为 `~/Cloud Volume/<bucket>` 的 sync-root 目录。用户习惯"挂载 = 盘符",自然会要求为 Cloud Files 桶选择 `X:` 式驱动器号,并与 UI 中已有的盘符选择(WinFsp)保持一致体验。

## Proposal

允许 Cloud Files 挂载在 UI 中选择空闲盘符,经 `subst <drive> <sync-root>` 建立映射;`windows_drive_mapping_windows.go` 已有的盘符发现/校验/`subst` 生命周期设施可以直接复用,实现成本很低。

## Alternatives considered

- **接受提案:`subst` 盘符别名** — 输在它只是目录别名:资源管理器对 `X:` 报告的是**宿主卷**(通常是 C:)的剩余空间,而不是桶配额;多桶各自映射到同一宿主卷时,几个"盘"显示同一错误容量,用户会把配额信息当真。
- **给 Cloud Files 写应用层 Statfs 让 `subst` 报正确容量** — Cloud Files 路径本质是本地目录视图,容量注入点不在我们控制的文件系统层;为一个别名 hack 挂载容量,不如把容量需求交给真正虚拟卷引擎。
- **(采纳)WinFsp 承载盘符 + 容量** — WinFsp 是用户态虚拟卷引擎,`Statfs` 按解析的桶配额报告 total/free,盘符由 WinFsp 自持;Cloud Files 保持路径呈现。见 [windows_platform](../../../features/windows_platform.md)。

## Consequences

- UI 明确不向 Cloud Files 提供盘符选择;`mount_bucket_dialog.dart` 只为 WinFsp 渲染盘符选择器,Cloud Files 仅路径;严格只读选择路由到 WinFsp(CFAPI 无法否决 Explorer 写入)。
- 防回潮锚点:不要在 UI 恢复 Cloud Files 盘符选择(windows_platform gotcha);`isWindowsDriveMount` 区分 WinFsp 自持盘符与 Cloud Files `subst` 映射,`Stop` 不得对 WinFsp 盘符调 `subst /D`。
- 保留条件:若未来 Cloud Files 出现应用可控的容量投影通道,此拒绝可重审;重审时新写一条 note 并链接本条。
