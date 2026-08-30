# Agent Note: Android 配置备份目录选择器按真实目标和可用宽度降级

Status: implemented

## Problem

首启还原没有已保存的 bucket,却把默认前缀 `cloud-volume-config-backups` 作为完整初始位置交给通用目录选择器。应用内路径匹配失败后回退首桶并继续读取该前缀,在 WebDAV/FTP/SFTP 上目录不存在即失败;手机内容宽度又不足以容纳四个固定单行按钮。失败后旧错误不会随成功导航清除,空快照结果也与 loading 混为一体。

## Decision

- `RemoteDirectoryPickerDialog.initial` 只在 bucket 与 profile 精确匹配时恢复;空或过期目标停在桶列表,由用户进入真实存在的目录。
- 底部以两个动作组表达语义,外层 `OverflowBar` 按实际宽度转为上下排列,组内 `Wrap` 继续保护较大字体,不依赖 Android 判断或固定断点。
- 每次目录请求先清旧错误,并以 generation 使较旧请求的迟到响应失效;首启快照列表独立记录 request-started、loading、error 与 empty。

## Alternatives considered

- **继续默认进入 `cloud-volume-config-backups`,把缺失目录当空目录** — provider 的“不存在”是有效语义,在通用桥接层吞掉会掩盖删除、路径拼错和权限问题;选择器不应伪造远端目录。
- **按 Android 或固定屏宽切换布局** — 按钮宽度还受中文文案与系统文字缩放影响,平台/断点判断不能覆盖真实溢出条件。
- **缩短标签、缩放文字或横向滚动** — 会牺牲动作含义、可读性与触控可达性,而操作区已有垂直空间可用。
- **自动创建默认目录** — 还原流程应只读取用户已有数据,未经确认写入远端既不能修复选错存储,也会制造一个看似有效但没有快照的目录。

## Consequences

- 新机还原先看到真实桶列表;已保存且仍有效的目标继续直达原目录。窄屏多占一行动作高度,目录列表的 `Expanded` 区域相应缩短。
- 缺失目录仍会如实报错,但用户返回根目录后的成功响应可恢复界面;更早请求之后才返回也不会污染当前目录。没有快照时显示可行动的空状态说明。
- `test/remote_directory_picker_dialog_test.dart` 覆盖手机/宽屏动作布局、系统文字缩放、无效初始目标、错误恢复、迟到响应隔离与空快照状态。
