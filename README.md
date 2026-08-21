# 云卷 / Cloud Volume

`云卷` 是一个面向 macOS、Windows、Linux 的 Flutter 客户端，用来管理 S3 兼容对象存储、WebDAV、百度网盘以及 FTP/SFTP 服务器，并把远端存储以更接近桌面文件管理器的方式呈现出来。

它不只是一个“桶列表 + 上传下载”工具，还包含本地缓存、可挂载 WebDAV 视图、应用级回收站、分享链接管理、任务队列，以及针对 Finder / Archive Utility 一类桌面工作流做过的本地优先优化。

桌面端继续保留原有 FFI + 本地挂载链路；Web 端则通过单独的 HTTP/API 服务暴露同一套对象管理能力，并额外提供每个 bucket 的 WebDAV 地址供浏览器外部客户端连接。

## 快速开始

clone 仓库后，直接执行 `make run` 即可启动桌面端（macOS / Linux / Windows 已封装好构建 Go bridge 与启动 Flutter 的完整流程）。

Flutter 版本兼容说明：`pubspec.yaml` 的 Dart SDK 约束为 `>=3.11.0 <4.0.0`，对应 Flutter 3.41（Dart 3.11）及以上均可直接 `make run`。如果你的 Flutter 自带的 Dart SDK 更旧导致 `flutter pub get` 报版本不满足，请用 `flutter upgrade` 升级到 stable 通道再重试。

## 功能导览

云卷把对象存储、WebDAV 和百度网盘放到同一个桌面工作台里：先添加账号，再进入文件管理；需要长期使用时可以挂载成系统目录，也可以创建本地目录与远端目录之间的同步任务。

首次启动会引导选择存储类型，目前支持 S3 兼容对象存储、WebDAV、百度网盘和 FTP/SFTP。

![首次启动选择账号类型](docs/screenshots/init1.png)

S3 账号支持 endpoint、access key、secret key、region 和 path-style URL 等配置；WebDAV 和百度网盘走各自的授权流程。新增账号的最后一步可选择要显示的桶，并为每个桶设置显示名称和入口子目录；不选择任何桶时会动态显示全部桶，包括服务端之后新增的桶。

![添加 S3 对象存储账号](docs/screenshots/init2.png)

账号管理页集中维护多个上游账号，新增账号后会直接出现在文件管理首页，不需要在不同连接之间来回切换。

![账号管理](docs/screenshots/account-page.png)

文件管理首页聚合展示所有账号下的 bucket / 根目录，并在列表中标出来源账号、配额、回收站和挂载状态。WebDAV 与百度网盘会读取服务端真实的已用/总容量，用户设置的自定义配额只覆盖显示总量。

![文件管理首页](docs/screenshots/main-page.png)

进入目录后可以浏览、搜索、上传、下载、新建目录、复制、移动、重命名、删除、分享、预览文件，并在桌面端支持拖拽上传和粘贴上传。

![远端文件浏览](docs/screenshots/file-page.png)

常用 bucket 可以挂载到本地目录，按系统文件管理器的方式读写远端对象；读写会先使用本地缓存和写回队列，再异步同步到远端。已通过远端确认前，挂载中尚未上传的内容直接由本地分块暂存提供字节读取。一个 namespace 内最近的本地 mkdir/write/rename/delete 会共享 quiet barrier，Finder 递归拷贝持续产生新操作时不会让早到的目录先单独同步；退出 drain 和人工立即执行仍会按依赖收尾，drain 与后台同步也会串行执行 provider 操作以保持覆盖式重命名的删除/移动顺序，且可在后台请求进行时响应取消。macOS Finder 批量写入新目录时，目标存在性探测也由本地目录视图回答，避免 SFTP 等高握手延迟上游退化为每个小文件一次远端查询。macOS 上 App 异常退出残留的挂载会在下次启动时自动清扫，不会留下指向已死本地服务的僵尸卷。

![挂载存储桶](docs/screenshots/mount.png)

文件同步页可以把本地目录绑定到远端桶目录，支持仅上传、仅下载和双向同步，并把同步产生的操作接入统一传输队列。

![文件同步任务](docs/screenshots/sync.png)

## 核心能力

- 多账号与多后端：统一管理 S3 兼容对象存储、WebDAV、百度网盘以及 FTP/SFTP 账号；首次启动、账号管理和文件管理都围绕同一套 profile 流程展开。每个账号可单独选择跟随全局代理、跟随系统、直连或自定义 HTTP/SOCKS5 代理，并可用统一的桶 allowlist、显示名称与入口子目录控制文件管理视图。FTP/SFTP 支持自定义端口和匿名登录。账号管理页可对单个账号启用/禁用——禁用的账号不会出现在文件管理页、不连接后端，但仍保留可随时重新启用。
- 配置备份：桌面端可在「设置 → 配置备份」把账号、代理和显示排序加密保存到指定远端存储；顶部开关控制功能启停，关闭时隐藏目标设置。加密采用用户自设的备份密码（不依赖连接凭证，换机器、换网络地址都不影响解密），新机器首次启动可从备份存储还原。目标可选已有账号，或点击「独立备份存储」后走简化配置流程（只选协议+填连接凭证，无需名称和桶映射），不显示在账号列表。保存位置改为单个远程目录选择器一次选定 bucket 与目录。开启后配置变更会自动备份，也可手动立即备份；备份历史通过可点击摘要打开拟态框查看并一键还原。新机器首次启动的「从备份存储还原」入口会先引导用户连接一个备份存储（如本地无已配置目标），再列出远端快照；加密的快照会显示锁标识并在还原前提示输入备份密码；还原成功后该备份目标（含备份密码）会自动保存到系统设置并开启自动备份，后续配置变更继续自动备份到同一位置。
- 文件管理：聚合 bucket / 根目录、目录浏览、列表/网格视图、搜索、多选、右键菜单、拖拽上传、粘贴上传、复制、移动、重命名、新建目录、下载和批量删除。
- 预览与缓存：桌面端支持图片预览、外部应用打开、另存为和下载；已下载文件会复用本地缓存，本地拖拽或粘贴上传成功后也会把本地副本登记为预览缓存，刚上传的文件双击即可打开。
- 桌面挂载：macOS 通过系统 WebDAV 卷挂载，Linux 通过 FUSE 挂载，Windows 支持 WebDAV、Cloud Files 与可选的 WinFsp 虚拟文件系统卷；带持久 profile identity 的文件管理页面与挂载的目录/对象信息读取总是使用同一持久 metadata namespace，不再因 mount session 是否存活切换到另一套视图。无身份的 legacy 配置仍保留活动挂载 local-first 快照与直连 fallback。活动目录会以退避间隔轮询远端，作为多客户端变更发现的基础，活跃轮询间隔可在「设置 → 同步设置」配置。Windows 严格只读会自动使用 WinFsp，避免 Explorer 产生仅本地的伪成功写入。Cloud Files 使用同步目录路径，不再提供会错误显示宿主磁盘容量的 `subst` 盘符；需要资源管理器显示桶级容量时选择 WinFsp。卸载 Cloud Files 时可选择保留或删除默认同步目录的本地缓存，并会提示先关闭占用文件；占用导致缓存删除失败时，挂载已安全解除，下一次会复用该根目录。目录 marker 的远端创建失败会在桶挂载操作旁显示错误详情，成功重试后自动清除；该状态不跨重启保留。桶级自定义配额会作为 Linux FUSE / Windows WinFsp 的文件系统总容量返回；WinFsp 未设置桶配额时回退到 Windows 高级设置中的全局虚拟容量。驱动缺失时支持应用内一键静默安装（内嵌 MSI）。
- 修改时间：对象列表和挂载统一按客户端本地时区展示远端时间。SFTP 只传 Unix 时间戳、不会携带服务器时区；挂载层会将已规范化的本地时间按本地时区还原，避免 Finder、FUSE 或 WinFsp 再次偏移。
- macOS 挂载诊断：Finder 复制目录时会先对目标发送不存在探测，挂载会在本地递归建立尚未同步的父目录而不等待远端；复制中重命名祖先目录时，子目录仍先写入已确认的远端父路径，再由目录移动带到最终名称，避免后台队列互等。若系统 `webdavfs_agent` 自身异常退出并移除卷，应用会保留待同步内容并明确报告意外断开，而不是静默显示成普通未挂载状态；探测瞬时失败也不会遗失部分启动的挂载会话，且这类未确认会话不会被误报为挂载成功。
- 文件同步：本地目录可定期同步到远端桶目录，支持上传、下载、双向同步、冲突策略、静默期、删除传播、重命名识别和空目录处理。跨客户端变更发现的 P2P 分期设计见 [docs/P2PSyncDesign.md](docs/P2PSyncDesign.md)。
- 统一远端任务队列：上传、下载、复制、移动、删除、挂载写回、文件同步和应用更新都投影为 `RemoteTask`，主列表展示有效远端操作，原始 journal/物理传输阶段可展开查看；支持依赖原因、进度、取消、重试、立即执行、按选择清理历史和 30 天自动保留。任务 ID 与物理快照都按 namespace 隔离，取消/验证状态可在重启后继续对账；Dart-only 预览、批量进度、挂载徽标和应用更新也走 `RemoteTaskStore` local adapter。旧 `TransferQueue` 只保留执行兼容，不作为任务 UI 真源。物理任务同时保留 profile 归属、下载本地目标、当前文件/分块范围与操作阶段；FTP、SFTP、WebDAV 和百度网盘的复制/移动/删除也会投影为同一物理任务，页面重命名复用带任务 ID 的移动路径，断点续传的历史字节不计入当前速度。
- metadata-backed 页面写操作的 Dart 队列只作为执行兼容层：主任务列表仅显示 Go journal 的有效 `sync:` 任务，上传/删除进度弹窗使用隔离的临时执行快照，避免同一远端操作出现两行。
- 这类临时执行快照只用于进度和后台运行提示，不提供取消；旧版本地兼容队列在升级时主动失效，未完成 metadata 操作由 Go journal 恢复。
- 任务队列会清除旧版本遗留的 metadata 物理快照；远端确认请求有明确超时，上传后确认失败会进入对账而不是重复覆盖写，并保留 SFTP 连接/权限错误，避免已同步文件长期显示为“验证远端”。
- 持久 inode 元数据核心：`go/mount/metadata` 使用 bbolt 为每个账号/桶视图维护本地 inode 与目录项 B+Tree、操作日志和可重建的元数据缓存；目录改名只更新两个目录项树和 inode 父边，不再依赖路径前缀重写。待同步文件内容采用固定 4 MiB、SHA-256 内容寻址分块，相同数据块只保留一份并按引用计数释放；块位于缓存目录，但未同步块会被缓存清理保护。挂载/page 的 `WritePath` 会先持久化并保护块，再在一个 bbolt 事务中提交 inode、generation、ContentRef、块 nlink 和 journal，避免大量小文件为一次写入重复 fdatasync；WebDAV LOCK 的协议占位不会制造零字节 metadata 写入，Finder 的 `.BC.T_*` 拷贝临时文件也只在最终改名时入队一次。已挂载桶会持有同一 metadata namespace 到实际卸载，避免页面读取与挂载读取争抢其生命周期；WebDAV、FUSE、WinFsp、Cloud Files 与带持久 profile identity 的页面 list/stat/create/upload/rename/move/delete 都通过这个持久树，metadata worker 是其唯一远端写回者，旧队列仅服务没有持久 profile identity 的执行兼容。metadata-backed 项在 Linux/WinFsp/Cloud Files 上还投影为稳定内部 OID；复制与递归目录上传会在有持久 identity 时明确拒绝，直到具备可原子提交的批量 journal 操作。
- 回收站与分享：提供应用级软删除、全局/桶级回收站、恢复、彻底删除、清空回收站，以及预签名分享链接的创建、续期、复制和删除。删除确认拟态框可在软删除时切换「永久删除」直接绕过回收站；目录删除按对象数实时显示确定进度条。移动/重命名/软删除/硬删除的源清理使用枚举时固定的 key 列表，并始终显式包含目录自身的 `dir/` 占位 key，避免某些 S3 兼容服务在递归列举时返回子文件却省略目录占位、导致源清理后留下空目录、重启后又重新出现的问题。软删除/移动/重命名的逐对象服务端复制与源删除自带容错重试，单个对象的临时性网关错误（502/超时等）不会直接中止整个目录操作。
- Web 与 CLI：Web 端通过 Go HTTP 服务提供对象管理 API、浏览器上传下载和 bucket WebDAV 入口；Linux 服务器可用 `cloud-volume-cli` 初始化配置并前台挂载 bucket。

## 界面设计

- 品牌名为 `云卷`，使用统一的侧边栏、列表和弹窗风格。
- 内嵌 `Source Han Sans CN`，减少不同平台的中文显示漂移。
- UI 基于 `shadcn_ui`，避免混用多套桌面/Material 风格控件。
- 主界面围绕“文件管理、账号管理、任务队列、回收站、分享管理、系统设置”六类核心页面展开。
- 列表页头部在批量选中后右侧操作按钮较多时，会自动按可用宽度把次要操作收进“…”更多操作下拉菜单，避免挤压标题导致副标题错位断行；回收站选中态仅显示已选数量、批量恢复和批量彻底删除，不再额外显示“清空选择”，操作区与普通状态保持相同高度。
- 账号管理页直接展示所有账号，并保留和桶列表一致的卡片 / 表格视图切换；列表视图可拖拽调整账号顺序（顺序会持久保存）；新增和编辑账号默认打开应用内拟态框（`showAppModal`）；仅在 Debug 且开启 `USE_MODAL_SUB_WINDOWS` 时才使用独立 OS 子窗口。新增表单采用三步式引导——选择接入协议、填写连接信息或完成 OAuth、设置桶列表显示；编辑模式跳过协议选择，直接进入连接信息。账号添加后会直接共存，不需要额外”连接”或切换当前账号。每个账号行有「状态」列：进入页面时并发探测可达性（正常 / 连接失败 / 检测中），禁用的账号直接显示「已禁用」。
- 文件管理首页会聚合展示所有已保存账号下的 bucket / 根目录，并在“来源”列明确标出账号名；列表和网格中的每个桶都显示容量进度条。WebDAV / 百度网盘按服务端已用容量填充并可悬浮查看详情；仅设置自定义总额度的 S3 显示中性空轨道和“用量未知”，没有任何总额度时显示同样的空轨道和“未设置额度”。桶设置中的自定义容量只覆盖总容量。列表视图可拖拽调整桶顺序（顺序会持久保存），方便直接并行管理多个上游。
- 设置页可配置缓存目录；未自定义时使用工作路径下的 `cache/`，文件预览缓存和挂载读写缓存都会归到这个根目录下。
- 设置页可配置挂载写入后的异步推送等待时间，默认 10 秒，适合想让本地保存更快回传远端的桌面工作流。
- 设置页可配置挂载元数据缓存策略：默认启用 1 分钟缓存，也可以直接关闭，关闭后目录浏览和文件信息读取会始终请求远端。
- 设置页里的回收站目录仍是全局默认值，并提供“自动清理”显式开关与保留天数；每个桶还可以在文件管理首页的“桶设置”里单独覆盖回收站目录、直接关闭回收站，或填写自定义配额（GB）。自定义配额会覆盖列表中的服务端配额，并在重新挂载后同步到 Linux FUSE / Windows WinFsp 的文件系统容量统计；它不会限制上传，0 或留空表示使用服务端配额（如支持）。macOS WebDAV 会在挂载握手前限时读取该容量或上游配额并通过 RFC 4331 提供给系统；Windows Cloud Files 的容量仍由宿主文件系统决定。
- 设置页新增「网络代理」配置区：支持跟随系统环境变量（默认）、直连、自定义代理三种模式。自定义代理支持 HTTP / SOCKS5 代理类型，可配置代理地址、端口、账号密码（账号密码可选），影响应用所有网络请求（S3、WebDAV、百度网盘）。应用更新的 GitHub Release 版本检查始终直连 GitHub API（公共下载镜像不支持 api.github.com）；如需加速安装包下载，可在「应用更新」区单独配置 GitHub 下载加速镜像（如 `gh-proxy.com`），仅作用于安装包下载。
- 设置页采用左侧锚点目录 + 右侧完整滚动页布局；左侧按“通用 / Windows / 关于”分组，点击应用更新、网络代理、缓存设置、关于云卷等条目会滚动定位到对应配置区块，入口只在鼠标悬停时显示轻量反馈。
- “关于”页的版本号现在统一来自构建时注入：本地开发默认显示 `dev`，CI/tag 发布构建会显示对应版本号。
- 通用设置“应用更新”区的 GitHub 下载加速镜像新增“测试镜像可用性”按钮，对当前选中镜像包裹真实 Release asset URL 做 HEAD 探测，直接显示镜像是否支持大文件下载，避免一键更新时下载停滞在 0B。一键更新使用镜像前也会自动预检，失败时给出明确提示并保留任务可取消。

- 通用设置顶部提供“检测更新”、“一键更新”和“GitHub 下载”。“检测更新”会读取 GitHub 最新 Release 信息（API 直连，单次最长约 30 秒并带有限重试）；发现新版本后桌面端可直接点击“一键更新”在应用内自动下载安装包并替换旧版本，安装完成后自动重启，无需手动卸载重装或执行命令行命令。Web 端仍跳转 GitHub 下载页。一键更新下载安装包完成后会做双重完整性校验：先比对本地文件大小与 GitHub Release asset 的 `size`，再用 asset 的 `digest`（`sha256:<hex>`）对落盘文件做 SHA-256 全文校验；任意一项不一致（多为加速镜像返回截断内容或错误页）时给出明确提示并清理残留文件，避免用坏包安装导致后续 `hdiutil`/解压报“映像数据已损坏”。本地缓存的安装包再次命中时也走同样的校验，不会反复复用坏包。下载过程中若遇到 GitHub 加速镜像在中段断流（常见报错 `stream error … INTERNAL_ERROR … received from peer`），会自动按已下载字节用 HTTP Range 续传重试，最多 5 次。
- Windows 一键更新优先使用绿色版 `yunjuan-windows-amd64.zip`，启动独立 updater 等待 Flutter 主进程和守护启动器退出，解压覆盖当前应用目录并重新启动 `cloud-volume.exe`；如果 Release 只有 Inno Setup `installer.exe`，仍会回退到静默安装器更新。
- Windows 发布包以 `cloud-volume.exe` 作为用户入口和守护启动器，实际 Flutter 主程序是同目录下的 `cloud-volume-app.exe`。主程序无法创建、在首个窗口出现前失败或运行中异常退出时，守护会在 `~/.cloud-volume/runtime/crashes/` 生成报告并弹窗提示；报告包含退出码、Windows/CPU 架构、关键程序文件的 SHA-256、bridge 日志尾部和最近一次 updater 日志，提交前可先检查其中的本地路径信息。正常关闭和应用更新不会弹出崩溃提示。
- 一键更新在传输队列仍有进行中的上传/下载时会先等待其完成，再开始下载安装包。

## 运行方式

### 首次启动

- 应用通过 Go FFI bridge 读取默认配置：macOS / Linux / Windows 统一使用用户主目录下的 `~/.cloud-volume/config.toml`，不再写到安装目录，避免在 `C:\Program Files\Cloud Volume` 这类需要管理员权限的目录下首次启动时写不进配置文件。
- 默认缓存目录跟随同一个工作路径：所有平台均为 `~/.cloud-volume/cache`；也可以在设置页改到其他目录。
- 设置页“缓存设置”卡片按“缓存目录设置 / 缓存占用 / 缓存清理”分区：目录区可选择、恢复默认或打开缓存目录（仅桌面端），占用区显示人类可读大小、文件数及受保护的待同步数据并可刷新统计，清理区支持按规则清理、清空缓存，以及“自动清理缓存 + 最大占用 MB + 最大保留天数”规则；待同步数据块不会被任何缓存清理操作删除。桌面端开启自动清理后会在启动时和每小时后台巡检一次。
- 升级启动时如果新位置还没有配置，会自动从旧的 `~/.remote-storage/config.toml`、`~/.remote-storage/profiles/*.toml` 迁移到新位置；旧版 Windows 安装目录下与 `cloud-volume.exe` 同级的 `config.toml` 也会一并迁移；迁移成功后会删除旧配置源，避免账号删除后又被旧配置恢复。
- 如果配置缺失或不完整，会先进入初始化配置页；初始化流程会先选择账号类型，目前支持 S3 对象存储、WebDAV、百度网盘和 FTP/SFTP，再进入对应账号表单。第一步仍是左右分栏（左侧品牌宣传 + 右侧协议选择）；进入第二步连接表单后会隐藏左侧宣传，改为全屏表单（宽屏下 S3 / WebDAV / FTP 字段两列排布），减少单页滚动。步骤切换时左侧品牌面板会平滑收起、右侧内容淡入，不再硬切或额外转圈。连接页左上角可点「返回」回到类型选择。
- S3 对象存储初始化默认网关为 `https://fgws3-ocloud.ihep.ac.cn`，仍需填写 `access_key_id/secret_access_key`，高级设置里可调整 `region` 与 path-style URL；WebDAV 初始化默认网关为 `https://webdav-ocloud.ihep.ac.cn`，并需填写用户名和密码；百度网盘初始化会通过桌面端 `oob` OAuth 流程打开授权页，用户需要把网页返回的授权码手动粘贴回应用完成登录。
- 如果访问密钥、签名或网络配置有误，初始化页会把常见 S3 / 网络错误转换成更友好的中文提示。
- 保存后进入主界面，后续设置页可以再次修改下载目录、显示选项、回收站策略等内容。
- 后续可在“账号管理”里同时维护多个上游账号；每个账号会保存为独立 profile，新增账号后会直接出现在文件管理首页，不需要额外切换当前连接。
- 设置页“账号重置”区块提供账号重置入口，确认后会清空所有已保存账号（含旧版 `~/.remote-storage` 与旧 Windows 安装目录下的遗留配置）并回到首次启动配置页；已挂载桶与缓存目录不受影响。
- 桌面端如果后续进入文件管理首页时连“桶列表”都拉取失败，错误卡片除了“重试”外还会提供“重新配置认证信息”，可直接回到 AK/SK/Endpoint 配置页修改后再试。
- Web 端后续每次打开会先检查浏览器 Cookie 里的会话 token；如果没有有效 token，会先进入登录页，校验通过后才允许访问文件管理、分享、回收站和系统设置。

### 本地开发

```bash
flutter pub get
go mod tidy
make run
```

`make run` 是本仓库的标准启动方式：

- macOS: 先构建 Go bridge 到 `bin/bridge/libremote_storage_bridge.dylib`，再以正确的 `DEVELOPER_DIR` 启动 Flutter macOS 应用
- macOS 调试挂载卡住时，可直接查看 `~/.cloud-volume/runtime/logs/bridge.log`；当前版本会记录 `mount-webdav-path`、`mount-webdav-registered`、`cleanup-stale`、`unmount`、`open-mount-path`、`[storage/quota-cache]` 与 `[mount/quota]` 等阶段。挂载使用非交互的 `mount_webdav -S`，命令成功后还必须等本次随机 loopback URL 的系统 mount 表项登记；命令超时或登记失败会清理半挂载并报错，绝不把普通目录当成成功卷。Finder 打开请求仍异步且按路径合并，卸载成功后才关闭本地 WebDAV。排查 WebDAV 目录可写/只读误判时，可搜索 `[webdav/access]`；排查新建目录失败时，可搜索 `[webdav/mkdir]`。
- macOS WebDAV 挂载的内容写入会先落到本地缓存，再按 quiet period 异步推送上游。Finder 为文件时间等属性发送的 `PROPPATCH` 元数据探测不会触发文件内容下载或重复上传；新建目录和新鲜目录快照中的缺失目标直接由本地视图返回，不会为每个待写小文件同步查询 SFTP。FTP、SFTP 和 WebDAV 上游的上传进度、成功和失败会及时反映到传输队列，不会在实际同步完成后继续停留在“等待同步”。挂载根目录通过 RFC 4331 向 `webdavfs` 返回容量：桶自定义容量优先，上游支持配额时同时返回实际已用量，因此 macOS `df` 可显示非零的总量、已用和可用空间；上游与配置均没有容量信息时仍保持未知。桶列表获取的配额会在 Go 后端缓存 5 分钟；挂载即使在 TTL 到期后也会先使用同一账号/桶最后一次已知容量并异步刷新，缓存目录、RootPrefix、挂载参数或显示设置不同不会造成缓存 miss。macOS `webdavfs_agent` 偶尔会延迟发布首次 `statfs`，此时第一次 `df` 可能暂时为 `0/0`，而后续查询显示服务端已在首次 `PROPFIND` 返回的容量。SFTP 挂载不推测预取子目录，也不后台重复轮询 Finder/Spotlight 递归扫到的深层目录；用户打开目录仍按需读取，SSH 建连与握手也服从请求超时。
- Linux: 先构建 Go bridge 到 `bin/bridge/libremote_storage_bridge.so`，并把它随 Linux bundle 一起安装后再启动 Flutter Linux 应用

平台相关命令：

- macOS: `make bridge-macos`, `make run-macos`, `make build-macos`
- Linux: `make bridge-linux`, `make run-linux`, `make build-linux`
- Windows: `make bridge-windows`, `make run-windows`, `make build-windows`

Windows 本地启动前提：

- 新 Windows 机器可以双击 `scripts\setup_windows_dev.bat` 一键准备开发环境；命令行也可以运行 `powershell -ExecutionPolicy Bypass -File .\scripts\setup_windows_dev.ps1`。脚本会通过 `winget` 安装/校验 Git、Go、Visual Studio 2022 Build Tools、MSYS2、WinFsp，并通过官方 `rustup-init` 安装 Rust；如果本机没有 `winget`，VS Build Tools、MSYS2 和 WinFsp 会回退到官方安装器或仓库内嵌的 WinFsp MSI 直链静默安装。脚本会按系统架构安装编译工具：x64 使用 MSYS2 UCRT64 `gcc/g++`，ARM64 使用 MSYS2 CLANGARM64 `clang/clang++`、原生 `aarch64-pc-windows-msvc` Rust，并补齐对应的 Visual Studio C++ 组件。Rust 使 CargoKit 插件在本地编译，避免 Windows ARM64 构建依赖 GitHub Release 预编译包。脚本还会写入 `FLUTTER_ROOT` / `BRIDGE_CC` / `BRIDGE_CXX` 和用户 `PATH`，并在未配置自定义 Go 模块代理时设置 `GOPROXY=https://goproxy.cn,direct`。
- 如果 Flutter 目录是管理员权限创建的，Git 可能报 `detected dubious ownership`；安装脚本和 Windows 运行脚本会自动把 Flutter 根目录加入当前用户的 Git `safe.directory`，避免 Flutter 取 engine version 失败。
- Flutter Windows 插件可能需要 symlink 支持；安装脚本和 Windows 运行/构建脚本会检测 Developer Mode。管理员权限下会尝试自动写入系统开关，否则仅提示用户稍后手动启用，不阻断初始环境配置。
- 如果希望安装完成后顺便构建本项目，可加 `-ValidateProject`；默认只做依赖安装、`flutter config --enable-windows-desktop` 和 `flutter doctor -v`，避免首次安装后立刻进入长时间构建。
- 需要可用的 Flutter Windows Desktop 环境。
- 需要可用的 MinGW-style C toolchain 供 Go `c-shared` bridge 使用，推荐 `MSYS2 UCRT64` 的 `gcc/g++`。
- 双击 `scripts\run_windows_debug.bat` 可按 Debug 模式启动 Windows 桌面端；双击 `scripts\build_windows.bat` 可一键构建 Release 包。Release 构建会写入 `git describe --tags --always --dirty` 版本标签，便于应用内更新正常比较；需要手动指定本地版本时可传 `-Version 1.2.3`。命令行也可以直接运行 `powershell -ExecutionPolicy Bypass -File .\scripts\run_windows.ps1`；如果只想构建不启动，可用 `-Build`，现在也兼容 `--build`。
- Windows 应用图标从现有 macOS 1024px 品牌位图生成，不重新绘制标志。修改品牌图标后运行 `powershell -ExecutionPolicy Bypass -File .\scripts\generate_windows_app_icon.ps1`，脚本会应用接近 macOS 的透明圆角遮罩，并写入 Windows 常用尺寸的 ICO 图层。

Windows 现在会在 `flutter run -d windows` / `flutter build windows` 期间自动构建 `bin/bridge/remote_storage_bridge.dll` 和 `cloud-volume-crash-reporter.exe`，并复制到 runner 目录。Release 目录中的 `cloud-volume.exe` 是守护启动器，`cloud-volume-app.exe` 是 Flutter 主程序；构建脚本会在打包前检查两者、报告器、updater 和 bridge 是否齐全。
Windows 调试启动不再依赖系统 `sqlite3.dll`。预览/打开文件用到的缓存索引现在通过 Go bridge 写入现有 bbolt `config.db`，Flutter 前端不再引入 `sqflite_common_ffi` / `sqlite3` 原生依赖，避免新机器缺少 SQLite 动态库导致界面闪退。
排查点击文件预览卡顿时，先在 设置 → 通用 → 日志设置 把日志等级切到“调试”，再在 `~/.cloud-volume/runtime/logs/bridge.log` 搜索 `[app/preview]`；日志会显示 `headObject`、cache index、缓存文件校验、下载任务和读取预览 bytes 的分段耗时。未手动设置时，开发调试版默认采集调试日志，正式发布版默认保持安静；采集结束后可切回“安静”或“常规”，避免正式环境长期写入高频诊断日志。
排查 Windows 挂载目录与客户端列表不一致时，同样先启用“调试”日志，再复现一次进入空目录的操作。日志文件位于 `%USERPROFILE%\.cloud-volume\runtime\logs\bridge.log`；搜索 `[mount/cloud-files] fetch-placeholders` 可核对本地目录到远端前缀的映射、返回条目数和回调错误，搜索 `retained-directory` 可确认复用缓存中的目录是重新启用按需枚举还是从普通目录修复为云占位目录。
如果本机配置了 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY`，请确保 `NO_PROXY` 包含 `127.0.0.1,localhost`；仓库自带的 `scripts/run_windows.ps1` 会自动补上这两个值，避免 `flutter run` 通过代理去连接本地 Dart VM service 而导致调试连接提前断开。

Linux 本地启动前提：

- 需要可用的 Flutter Linux Desktop 环境。
- 需要 `clang`、`cmake`、`ninja-build`、`pkg-config`、`libgtk-3-dev`、`fuse3` 以及可用的 Go CGO 编译链。
- Linux runner 现在也会在 `flutter run -d linux` / `flutter build linux` 期间自动构建 `bin/bridge/libremote_storage_bridge.so`，并把它安装到 bundle 的 `lib/` 目录，避免打包后的可执行文件因缺少 bridge 而无法启动。
- Linux 挂载现在使用用户态 FUSE mount，把 bucket 暴露到 `~/Cloud Volume/<bucket>`，目录读取、按需下载、本地暂存、延迟写回、删除和改名都继续复用现有 Go 侧本地优先逻辑。
- 仅使用 CLI 挂载时，至少需要 `fuse3`、`fusermount3` 和可用的 `/dev/fuse` 设备；Ubuntu / Debian 可先执行 `sudo apt install -y fuse3`。

### Linux CLI 挂载

仓库现在额外提供 `cloud-volume-cli`，用于在没有桌面环境的 Linux 服务器上初始化配置并前台挂载 bucket。

构建：

```bash
make cli
```

首次初始化：

```bash
./bin/cloud-volume-cli init
```

直接执行 CLI 会默认进入交互 shell：

```bash
./bin/cloud-volume-cli
```

`init` 会交互式提示输入这些关键配置：

- `endpoint`
- `region`
- `access key id`
- `secret access key`
- `use_path_style`

初始化时会直接用新输入的 endpoint 和凭证发起 `ListBuckets` 请求：

- 如果 bucket 列表可用，你可以用上下键选择一个默认 bucket
- 也可以选择“暂不设置默认 Bucket”
- 如果暂时没设置默认 bucket，后续第一次执行对象操作或挂载命令时，CLI 会再即时拉取 bucket 列表让你选

默认会立即校验 endpoint、凭证和 bucket 可访问性；如果当前账号没有 `ListBuckets` 权限，或者你只是想先保存配置，可以改用：

```bash
./bin/cloud-volume-cli init --skip-validate
```

挂载指定 bucket 到指定目录：

```bash
./bin/cloud-volume-cli mount --bucket media --mount-point /mnt/media
```

追加写入场景如果希望尽早把完整 multipart 分块预推到远端，可以打开 `--auto-sync`：

```bash
./bin/cloud-volume-cli mount --bucket media --mount-point /mnt/media --auto-sync
```

如果需要手工放大 multipart 并发，可以再叠加 `--worker`：

```bash
./bin/cloud-volume-cli mount --bucket media --mount-point /mnt/media --auto-sync --worker 16
```

也支持位置参数：

```bash
./bin/cloud-volume-cli mount media /mnt/media
```

对象操作：

```bash
./bin/cloud-volume-cli bucket list
./bin/cloud-volume-cli ls
./bin/cloud-volume-cli ls docs
./bin/cloud-volume-cli mkdir docs/archive
./bin/cloud-volume-cli rm docs/archive
./bin/cloud-volume-cli put ./demo.txt docs/demo.txt
./bin/cloud-volume-cli get docs/demo.txt ./demo.txt
./bin/cloud-volume-cli put ./photos
./bin/cloud-volume-cli get docs/archive ./archive-local
```

说明：

- 不传 `--bucket` 时，会回退到 `~/.cloud-volume/config.toml` 里的默认 `bucket`
- 如果既没有传 `--bucket`，配置里也没有默认 bucket，CLI 会先拉取 bucket 列表让你选择
- 不传 `--mount-point` 时，仍使用默认目录 `~/Cloud Volume/<bucket>`
- `mount` 会前台常驻；Linux CLI 下按 `Ctrl+C` 会先等待当前 bucket 里尚未推送完成的写回任务刷完，再执行卸载
- 自定义挂载目录必须为空目录；CLI 不会删除你自定义目录里的已有内容
- 大文件写回当前使用可恢复 multipart 上传，已完成分块会记录到本地 `.uploading.json` 状态里；后续重试会跳过已完成分块，并且会并发上传剩余分块来提升多 GB 文件的同步速度
- `--worker` 可显式指定 multipart 上传并发；不指定时默认按 CPU 核数动态取值，最小 `4`、最大 `10`
- `--auto-sync` 会在 Linux FUSE 检测到顺序追加写时，后台预上传已经完整落盘的 multipart 分块；遇到随机写、覆盖写、truncate 或显式属性改动时，会自动降级回原来的“本地落盘后异步整体写回”语义，避免破坏现有一致性
- 即使启用了 `--auto-sync`，最终文件关闭后的 quiet-period 自动推送和卸载时的 drain 推送仍然保留，用于补齐最后不足一个完整分块的尾部数据并完成 multipart
- Linux 挂载缓存文件现在默认落到 `~/.cloud-volume/cache/mounts/<bucket>/`，也会跟随设置页里的自定义缓存目录变化
- `put` / `get` 现在默认支持目录递归；上传目录时会同步创建远端目录占位符，下载目录时会在本地重建目录树
- `rm` / `delete` 当前走硬删除，对象和前缀都会直接从 bucket 删除，不会进入应用级回收站

查询和卸载：

```bash
./bin/cloud-volume-cli status --bucket media
./bin/cloud-volume-cli unmount --bucket media
```

如果你挂载时用了自定义目录，也可以直接按目录查询和卸载：

```bash
./bin/cloud-volume-cli status --mount-point /mnt/media
./bin/cloud-volume-cli unmount --mount-point /mnt/media
```

当前 `mount` / `unmount` 真正的挂载能力仍然只在 Linux 上生效；但 CLI 本身会继续构建 Windows amd64、macOS amd64/arm64、Linux amd64/arm64 版本，便于统一分发 `init`、配置检查和后续扩展命令。

### CLI Shell

默认进入的 shell 会保存当前 bucket 和当前远端目录上下文，减少重复输入。

常用 shell 内命令：

- `bucket`：弹出 bucket 选择器并切换当前 bucket
- `bucket list`：列出可用 bucket
- `bucket <name>`：直接切换当前默认 bucket
- `pwd`：输出当前远端目录
- `cd docs/api`：进入远端目录，支持相对路径、`..` 和绝对路径
- `mkdir docs/archive`：创建远端目录占位符
- `rm docs/archive`：递归硬删除远端对象或目录
- `ls` / `ls subdir`：列出当前目录或子目录
- `put ./local.txt`：上传到当前目录，默认远端文件名取本地 basename
- `put ./folder`：递归上传整个目录树到当前目录
- `get report.csv`：从当前目录下载文件
- `get reports/2026`：递归下载整个远端目录树
- `mount --mount-point /mnt/media`：挂载当前 bucket
- `status` / `unmount`：查看或卸载当前 bucket 的挂载
- `Tab`：补全命令和远端路径
- `Up/Down`：浏览历史记录，持久化到 `~/.cloud-volume/runtime/cli_history`

示例：

```bash
./bin/cloud-volume-cli
cloud-volume> bucket
cloud-volume[media:/]> cd reports/2026
cloud-volume[media:/reports/2026]> ls
cloud-volume[media:/reports/2026]> put ./summary.csv
cloud-volume[media:/reports/2026]> get summary.csv ./summary.csv
```

CLI 发布产物命名：

- Lite CLI：`yunjuan-cli-lite-linux-amd64.tar.gz`、`yunjuan-cli-lite-linux-arm64.tar.gz`、`yunjuan-cli-lite-darwin-amd64.tar.gz`、`yunjuan-cli-lite-darwin-arm64.tar.gz`、`yunjuan-cli-lite-windows-amd64.zip`
- Full CLI：`yunjuan-cli-full-linux-amd64.tar.gz`、`yunjuan-cli-full-linux-arm64.tar.gz`、`yunjuan-cli-full-darwin-amd64.tar.gz`、`yunjuan-cli-full-darwin-arm64.tar.gz`、`yunjuan-cli-full-windows-amd64.zip`

其中：

- `cloud-volume-cli` 对应 lite 版，只包含原有 CLI 能力。
- `cloud-volume-cli-full` 对应 full 版，额外内嵌 Flutter web 静态资源并提供 `web` 子命令，可单文件启动浏览器控制台。
- `cloud-volume-cli`、`cloud-volume-cli-full web` 和独立的 `cloud-volume-web` 入口都支持 `version` / `--version` 打印当前版本号。
- 原有独立 Web 运行时产物 `yunjuan-web-linux-*` 仍会继续发布，适合单独部署 `cloud-volume-web`。
- Windows 安装包仍由 Inno Setup 生成；如果要减少 SmartScreen/Defender 的“未知发布者”拦截，需要在构建环境里提供 Authenticode 代码签名证书，并通过 `WINDOWS_SIGN_PFX_PATH` + `WINDOWS_SIGN_PFX_PASSWORD` 或 `WINDOWS_SIGN_SUBJECT` 注入签名参数。

本地如果需要构建 CLI 发布包，可以运行：

```bash
make cli-release
make cli-release-full
```

### Web 本地开发

先构建 Flutter Web 静态资源，再启动 Go HTTP 服务：

```bash
flutter pub get
make build-web
make run-web
```

`make run-web` 会执行两件事：

- 构建 Flutter Web 前端到 `build/web`
- 启动 `go run ./cmd/web --listen :8080 --static-root build/web`

然后打开 `http://127.0.0.1:8080`。

如果想测试新的单文件 full CLI，也可以直接运行：

```bash
./bin/cloud-volume-cli-full web --listen :8080
```

这个子命令会优先使用二进制内嵌的 Flutter web 静态资源，不依赖外部 `build/web` 目录。

Windows Cloud Files 挂载会自动忽略 `desktop.ini`、`Thumbs.db`、Office `~$*.docx/xlsx/pptx` 锁文件和常见 `~wr*.tmp` 临时文件，避免这些短生命周期本地噪声进入远端同步队列。

Web 端行为和桌面端有几个关键差异：

- 不走 FFI，也不做本地文件系统挂载。
- 桶列表中的“挂载/打开挂载目录”会替换成查看 WebDAV 地址。
- 上传使用浏览器选中的内存文件，下载使用浏览器地址或新标签页。
- 浏览器登录依赖 Cookie 会话；标准 WebDAV 客户端则使用 HTTP Basic Auth。默认情况下两者都会复用当前 `AK/SK`，也可以在系统设置里改成独立的 WebDAV 账号密码。

## 配置项

初始化页会按账号类型保存连接配置。

S3 对象存储账号包括：

- `endpoint`：S3 兼容端点地址
- `region`：区域
- `access_key_id`：访问密钥 ID
- `secret_access_key`：访问密钥 Secret
- `use_path_style`：是否启用 path-style URL

WebDAV 账号包括：

- `endpoint`：WebDAV 服务地址
- `webdav_username`：WebDAV 用户名
- `webdav_password`：WebDAV 密码

通用存储配置还包括：

- `bucket`：默认桶名
- `root_prefix`：可选的根前缀

其他应用级设置包括：

- 默认下载目录
- 是否隐藏 `.` 开头文件
- 回收站目录名
- 回收站自动清理保留天数（默认关闭，设置为非负数才启用）
- 主题强调色
- **局域网 P2P 同步**（`p2p_enabled`，默认开启）：同局域网内登录同一账号的多台设备通过 mDNS 自动发现，写入完成后即时刷新受影响目录；读取时优先从拥有同版本完整缓存或刚确认上传源的设备拉取，失败或版本变化自动回退远端。**多账号并行发现**：每个启用 P2P 的账号档案各自广播自己的账号指纹，两台设备只要共享任意一个账号即可互相发现，与当前活跃账号无关；设置页的设备列表会标注与每台对端共享的账号。可在「设置 → 局域网同步」开关（按账号档案独立保存）；该设置卡片的开关行、分组标题与设备列表容器与其他设置卡片保持同一套视觉规范。
- **P2P 传输分块大小**（`p2p_chunk_size_mb`，默认 4 MB，范围 1-64 MB）：局域网内容直传的原始字节分块大小；每个文件最多 4 路并发分块流。
- WebDAV 登录账号与密码
- Windows 下的设置页会显示独立的 Windows 锚点分组，承载写回并发和挂载恢复等平台专属项；已失效的“此电脑”入口开关不再展示，非 Windows 构建不会显示该分组。

## 架构概览

- Flutter：桌面 UI、页面状态、任务展示、配置与交互层
- Go bridge / web API / CLI：配置读写、S3 操作、挂载实现、分享链接、回收站、任务快照；桌面端通过 FFI 调用，Web 模式下同一套 Go 能力通过 HTTP/JSON + WebDAV 暴露给浏览器，CLI 则提供 Linux 服务器上的交互式初始化和前台 FUSE 挂载入口
- Desktop mount backends：macOS 走系统 WebDAV 卷挂载，Linux 走用户态 FUSE 挂载，Windows 同时保留 Cloud Files 与 WebDAV 映射盘方案
- 本地缓存与 overlay：保证挂载场景下的本地优先可见性与恢复能力

## 发布

推送形如 `v0.0.1` 的语义化版本标签后，会触发 GitHub Actions 构建并自动创建 / 更新对应 GitHub Release：

本地可在提交干净工作区后执行 `make push`：在现有最新 `v*` 标签基础上自动递增 patch（如 `v1.1.4` → `v1.1.5`；`v1.1.9` → `v1.2.0`；`v1.9.9` → `v2.0.0`），打附注标签并 `git push` 当前分支与标签。需要升 minor/major 时用 `BUMP=minor make push` 或 `BUMP=major make push`。

- macOS `universal` / `arm64`：桌面版 `dmg`、`zip`
- Windows `amd64`：桌面版 `installer.exe`、`zip`
- Linux `amd64`：桌面版 `tar.gz`、`AppImage`
- Linux / macOS / Windows：Lite CLI 发布包
- Linux / macOS / Windows：Full CLI 发布包，内含 `cloud-volume-cli-full` 单文件二进制
- Linux `amd64` / `arm64`：Web 服务端 `tar.gz`，内含 `cloud-volume-web` 和对应静态站点

CLI / Web 发布形态说明：

- Lite CLI 继续保留现有 `cloud-volume-cli` 行为，不包含 `web` 子命令。
- Full CLI 新增 `cloud-volume-cli-full`，通过内嵌文件系统提供 `web` 子命令，适合单文件分发。
- 独立 Web 版继续保留 `cloud-volume-web`，适合把静态资源和服务端一起解压部署。

Linux 桌面版同时提供 `tar.gz` 和 `AppImage`：

- `tar.gz` 更通用，适合手动解压部署和兼容性更保守的桌面环境。
- `AppImage` 适合直接下载后单文件运行，不依赖目标机器的发行版包管理器。

产物都包含对应平台的 Flutter 桌面壳和 Go bridge。
发布流程会自动生成包含更新记录、macOS 打开提示处理方法、国内 GitHub 加速下载表格以及校验信息的 Release 文案；下载表格会按当前 tag 和实际产物列出 GitHub 原始链接、`gh-proxy` 与 `ghfast` 加速链接，方便用户直接点击。
macOS 的 DMG 现在还会额外附带一个 `修复已损坏问题.txt`，把应用拖到 `Applications` 后可打开它，按说明在终端执行 `xattr` 命令移除隔离属性（之前的 `.command` 双击脚本本身也会被 Gatekeeper 隔离，已替换为纯文本引导）。
打包后的桌面版现在会优先加载应用 bundle 内置的 Go bridge 动态库，不再要求从仓库目录启动才能正常运行。macOS app bundle 内 bridge dylib 的查找顺序为 `Contents/Frameworks/` 优先于 `Contents/MacOS/`，避免早期调试运行遗留在 `MacOS/` 下的旧 dylib 被误加载导致新方法（如 `install_app`）报 "unsupported bridge method"；`make build-macos` 在写入 dylib 前会先清除 `Contents/MacOS/` 下可能残留的旧副本。


## 许可证

本项目基于 [MIT License](LICENSE) 开源。

## 当前状态

这是一个明显偏“桌面工作流优先”的对象存储客户端，而不是简单的 Web 面板移植版。
如果你希望在对象存储上获得更接近 Finder / 资源管理器的体验，这个仓库就是围绕这个目标持续演进的。
## Windows Mount Modes

Windows now keeps three mount modes available side by side so behavior can be compared without reverting code:

- `cloud_files_cached`: uses the native Cloud Files shell, but hydration goes through the existing cached-download, transfer-queue, and async writeback flow used by the mature mount layer.
- `cloud_files_direct`: uses the native Cloud Files shell and reads placeholder data directly from S3 for direct-path testing.
- `webdav`: keeps the mapped-drive fallback that mounts the local WebDAV server into Explorer as a network drive.

The active mode is stored in config as `windows_mount_mode` and can be changed from Settings. Remount the bucket after switching modes.
Mounted writeback uploads now also respect configurable `writeback_quiet_seconds` and `windows_writeback_concurrency` settings. The default quiet wait is `10` seconds, and the default Windows upload concurrency is `4`.
The cached Cloud Files writeback path now persists queued uploads in per-process queue snapshots under `~/.cloud-volume/runtime/mounts/<bucket>/writeback/queue-<pid>.json`, merges repeated writes by virtual path, compacts old queue files on remount, and resumes those pending uploads after a remount instead of dropping them with the old in-memory session queue.
Unmount now releases the Cloud Files shell, watcher, and sync-root registration without waiting for the full writeback queue to flush first. As long as the app process stays alive, delayed uploads continue in the background after unmount and still honor the configured quiet-period debouncing.
Cloud Files mounts on Windows now keep a stable sync-root path at `~/Cloud Volume/<bucket>` instead of creating a timestamped directory on each mount, so Explorer shortcuts, task recovery, and user-visible mount paths stay deterministic across remounts.
The Windows Cloud Files mount dialog uses a sync-root path only. It does not offer a `subst` drive because such a mapping always reports the host disk's capacity, not the bucket's capacity. WinFsp virtual-file-system mounts are different: they mount directly to a selected drive letter, return the configured bucket quota to Explorer, hide path mounting, and block the request until a free letter is available.
Settings also expose a force-reset mount action that calls `cleanup_mounts` to clear stuck bucket mounts, stale sync roots, and cached mount state before retesting Explorer writes.
If a remount fails because `~/.cloud-volume/runtime/mounts/<bucket>/writeback/queue-<pid>.json` is still locked by a leftover `cloud-volume.exe`, the mount now returns a normal actionable error instead of panicking, and Windows Settings also expose an `结束残留占用进程` action to kill those stale local runner processes before retrying.
The Cloud Files placeholder path coalesces repeated directory fetch callbacks. Remote polling creates new entries, updates existing changed entries with `CfUpdatePlaceholder` and dehydrates changed files so Explorer reloads their contents, and removes known remote entries only when no local writeback owns the path. This keeps an open sync root current without overwriting delayed local writes.
## Runtime Logs

Go bridge runtime logs are written to `~/.cloud-volume/runtime/logs/bridge.log` on macOS, Linux, and Windows when the current log level allows them. The log level is configured in Settings and applies to both Flutter-forwarded diagnostics and Go backend logs; release builds default to silent logging unless the user enables collection.

## UI Responsiveness

Flutter now dispatches synchronous Go bridge calls from a background isolate before entering the FFI layer. This keeps bootstrap loading, bucket refreshes, mount-status probes, and object metadata lookups from blocking the desktop UI thread when the bridge is waiting on network or mount work.

## Desktop Window Sizing

The desktop runners now use adaptive startup sizing on all three platforms:

- Linux keeps shrinking the first window based on the current monitor size so the setup form stays visible on smaller displays.
- Windows now applies the same low-resolution startup sizing strategy in the native runner before the Flutter surface is shown.
- macOS now resolves the initial centered frame from the visible screen area as well, and also lowers the minimum resizable size when the display is smaller than the normal default window.

### Windows Cloud Files deletion consistency

Deleting a mounted object from the app file list also removes its existing Windows Cloud Files placeholder. App-side directory creation, uploads, copies, and moves project new or overwritten objects into the sync root as placeholders when their parent directory is present. Pending delayed writeback for deleted paths is canceled first, and provider-owned filesystem callbacks are suppressed so Explorer and the remote object list converge without recreating or double-deleting objects.

On confirmed application exit, the window and tray icon disappear immediately while active mounts are cleaned in the background. Windows Cloud Files sessions disconnect and deregister their sync roots before process termination; hiding to the tray keeps mounts active by design.

When one or more mounts are active, closing the app explicitly warns that Exit will unmount them. Choose "后台运行" to keep the process and mounts active.

With no active mounts, closing still offers minimize/hide-to-tray instead of forcing an immediate exit.

- 桌面端诊断日志由设置页统一控制，Flutter `AppLog` 与 Go backend 日志共享 `Silent` / `Error` / `Info` / `Debug` 等级。
