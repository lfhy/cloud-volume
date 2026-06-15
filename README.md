# 云卷 / Cloud Volume

`云卷` 是一个面向 macOS、Windows、Linux 的 Flutter 桌面客户端，用来管理 S3 兼容对象存储，并把对象存储以更接近桌面文件管理器的方式呈现出来。

它不只是一个“桶列表 + 上传下载”工具，还包含本地缓存、可挂载 WebDAV 视图、应用级回收站、分享链接管理、任务队列，以及针对 Finder / Archive Utility 一类桌面工作流做过的本地优先优化。

## 仓库截图

![云卷主界面](docs/screenshots/main-page.png)

## 核心能力

- 文件管理：桶列表、目录浏览、列表/网格视图、右键操作、搜索、多选、批量下载/删除。
- 挂载访问：把当前桶挂载成 macOS 可见的 WebDAV 卷，支持在 Finder 里直接读写。
- 本地优先：挂载写入、删除、改名、移动先落本地缓存与 overlay，再异步回写远端。
- 断点续传：大文件挂载上传支持可恢复 multipart writeback，挂载下载支持复用完整缓存与 `.downloading` 分片续传。
- 回收站：应用级软删除、全局回收站 / 桶级回收站、恢复、彻底删除、分页与无限滚动。
- 分享管理：为文件创建预签名下载链接，集中管理分享记录、续期、复制与删除。
- 任务队列：统一展示上传、下载、复制、移动、删除、挂载写回，支持筛选、取消、持久化恢复。
- 桌面体验：托盘图标、透明标题栏、统一中文字体、面向桌面鼠标操作的上下文菜单和固定表头列表。

## 界面设计

- 品牌名为 `云卷`，使用统一的侧边栏、列表和弹窗风格。
- 内嵌 `Source Han Sans CN`，减少不同平台的中文显示漂移。
- UI 基于 `shadcn_ui`，避免混用多套桌面/Material 风格控件。
- 主界面围绕“文件管理、任务队列、回收站、分享管理、系统设置”五类核心页面展开。- 系统设置包含**缓存管理**卡片，可查看本地缓存大小并一键清理下载缓存与挂载缓存。
## 运行方式

### 首次启动

- 应用通过 Go FFI bridge 读取 `~/.remote-storage/config.toml`。
- 如果配置缺失或不完整，会先进入初始化配置页。
- 保存后进入主界面，后续设置页可以再次修改下载目录、显示选项、回收站策略等内容。

### 本地开发

```bash
flutter pub get
go mod tidy
make run
```

`make run` 是本仓库的标准启动方式：

- 先构建 Go bridge 到 `bin/bridge/libremote_storage_bridge.dylib`
- 再以正确的 `DEVELOPER_DIR` 启动 Flutter macOS 应用

平台相关命令：

- macOS: `make bridge-macos`, `make run-macos`, `make build-macos`
- Linux: `make bridge-linux`, `make run-linux`, `make build-linux`, `make appimage`
- Windows: `make bridge-windows`, `make build-windows`

### AppImage 构建

在 Linux 上运行 `make appimage` 即可一键构建 AppImage 包，产物位于 `dist/` 目录。

该流程会依次：编译 Go bridge → 编译 Flutter Linux release → 组装 AppDir → 下载 appimagetool → 打包为 AppImage。

如需更多控制，也可直接使用 `./scripts/build_appimage.sh`，支持 `--version`、`--arch`、`--skip-bridge` 等选项。

## 配置项

初始化页会保存这些 S3 兼容存储配置：

- `endpoint`：S3 兼容端点地址
- `region`：区域
- `bucket`：默认桶名
- `access_key_id`：访问密钥 ID
- `secret_access_key`：访问密钥 Secret
- `root_prefix`：可选的根前缀
- `use_path_style`：是否启用 path-style URL

其他应用级设置包括：

- 默认下载目录
- 是否隐藏 `.` 开头文件
- 回收站目录名
- 回收站自动清理保留天数
- 主题强调色

## 架构概览

- Flutter：桌面 UI、页面状态、任务展示、配置与交互层
- Go bridge：配置读写、S3 操作、挂载实现、分享链接、回收站、任务快照
- WebDAV mount：给 Finder / 桌面应用提供可读写挂载入口
- 本地缓存与 overlay：保证挂载场景下的本地优先可见性与恢复能力

## 发布

推送标签如 `v0.0.1` 后，会触发 GitHub Actions 构建桌面发行版：

- macOS `amd64` / `arm64` / `universal`
- Windows `amd64` / `arm64`
- Linux `amd64` / `arm64`

产物包含各平台对应的 Flutter 桌面壳与 Go bridge。

## 当前状态

这是一个明显偏“桌面工作流优先”的对象存储客户端，而不是简单的 Web 面板移植版。
如果你希望在对象存储上获得更接近 Finder / 资源管理器的体验，这个仓库就是围绕这个目标持续演进的。
