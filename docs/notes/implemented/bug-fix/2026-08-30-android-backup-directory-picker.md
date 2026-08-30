# Agent Note: Android 配置备份目录选择器按真实目标、单根别名和可用宽度降级

Status: implemented

## Problem

首启还原没有已保存的 bucket,却把默认前缀 `cloud-volume-config-backups` 作为完整初始位置交给通用目录选择器。应用内路径匹配失败后回退首桶并继续读取该前缀,在 WebDAV/FTP/SFTP 上目录不存在即失败;手机内容宽度又不足以容纳四个固定单行按钮。

同一选择器的桶、目录、文件行复用了桌面 `FileListTile` 的固定元数据列,在手机上会把 `boot`、`home` 等短名称也挤成省略号。WebDAV、百度网盘、FTP、SFTP 的唯一合成桶还会暴露登录用户名等后端名字(常见为 `root`),但还原流程需要稳定的「备份存储」语义,同时不能改写桥接和持久化使用的真实桶 identity。失败后旧错误不会随成功导航清除,空快照结果也与 loading 混为一体。

## Decision

- `RemoteDirectoryPickerDialog.initial` 只在 bucket 与 profile 精确匹配时恢复;空或过期目标停在桶列表,由用户进入真实存在的目录。
- 底部以两个动作组表达语义,外层 `OverflowBar` 按实际宽度转为上下排列,组内 `Wrap` 继续保护较大字体,不依赖 Android 判断或固定断点。
- 选择器三类列表行由局部 `LayoutBuilder` 读取实际列表宽度;`<560` 时使用 `FileListTile.compact`,释放固定元数据列占用的空间,宽屏维持文件列表的标准列布局。
- 首启备份专用模型把 WebDAV、百度网盘、FTP、SFTP 的唯一合成桶显示为「备份存储」,但保留原 `BucketInfo.name`、entry id 和 config;它用真实桶名与空 prefix 构造精确初始目标并自动进入。S3 不套该规则,即使只有一个桶也显示真实桶列表。
- Debug 目录选择子窗口的 JSON 参数携带 `displayName` 与 `rootPrefix`,使展示别名和限定根目录与应用内路径一致。
- 每次目录请求先清旧错误,并以 generation 使较旧请求的迟到响应失效;首启快照列表独立记录 request-started、loading、error 与 empty。

## Alternatives considered

- **继续默认进入 `cloud-volume-config-backups`,把缺失目录当空目录** — provider 的“不存在”是有效语义,在通用桥接层吞掉会掩盖删除、路径拼错和权限问题;选择器不应伪造远端目录。
- **按 Android 或固定屏宽切换布局** — 按钮宽度还受中文文案与系统文字缩放影响,平台/断点判断不能覆盖真实溢出条件。
- **只把名为 `root` 的桶改名,或直接改写 `BucketInfo.name`** — S3 可以存在真实的 `root` 桶,按名称猜测会误伤;改写 identity 还会让桥接访问不存在的桶或把错误值持久化。展示别名必须与真实 identity 分离。
- **所有单桶存储都自动进入并隐藏桶名** — S3 的单桶仍是真实业务桶,桶名对确认目标有意义;只有已知单根 provider 的合成桶适合备份语义别名。
- **全局压缩 `FileListTile` 的桌面元数据列** — 会改变文件管理页的列对齐和信息密度;问题只发生在 picker 的局部可用宽度,由 picker 包装三类行更可控。
- **缩短标签、缩放文字或横向滚动** — 会牺牲动作含义、可读性与触控可达性,而操作区已有垂直空间可用。
- **自动创建默认目录** — 还原流程应只读取用户已有数据,未经确认写入远端既不能修复选错存储,也会制造一个看似有效但没有快照的目录。

## Consequences

- WebDAV、百度网盘、FTP、SFTP 的单根还原直接看到「备份存储」根目录内容,但桥接调用和还原后固化的目标仍使用真实桶名;S3 继续从真实桶列表选择。已保存且仍有效的目标继续直达原目录。
- 窄屏多占一行动作高度,目录列表的 `Expanded` 区域相应缩短;紧凑行把来源/大小移到标题下方,宽屏文件列表列布局不变。Debug 子窗口的展示与限定根目录不再因序列化降级。
- 缺失目录仍会如实报错,但用户返回根目录后的成功响应可恢复界面;更早请求之后才返回也不会污染当前目录。没有快照时显示可行动的空状态说明。

## Testing

`test/remote_directory_picker_dialog_test.dart` 覆盖手机/宽屏动作布局、1.5 倍文字缩放、短名称无视觉截断、四种单根 provider 的别名/identity、单桶 S3、debug 参数 round-trip、确认结果、无效初始目标、错误恢复、迟到响应隔离与空快照状态。
