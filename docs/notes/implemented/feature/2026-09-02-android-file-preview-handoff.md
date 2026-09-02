# Agent Note: Android 文件预览交接与 Markdown 渲染

Status: implemented

## Problem

Android 文件预览沿用桌面进程启动和本地路径的假设，系统不能读取应用私有缓存，导致无法可靠地交给其它应用打开。`.md` 也未被识别为可预览类型，用户只能看到不支持提示。

## Decision

Android 预览从同一份已校验的本地缓存读取 Markdown，由 `flutter_markdown_plus` 渲染可选择的 GitHub Flavored Markdown；为避免移动端同步解码和解析超大文本，`headObject` 后限制内嵌 Markdown 为 8 MiB。不受信任 Markdown 中的图片始终用无 I/O 占位替代，绝不自动解析或加载 `http(s)`、`file:`、`data:` 等 URI。Android 的「下载到缓存」复用 `<cacheDir>/files/<bucket>/<key>`，不打开系统另存为。外部打开时，原生宿主把单个目标复制到专用 cache 子目录，`FileProvider` 只为这份副本签发临时只读 `content://` URI，并交给系统应用选择器。

## Alternatives considered

- **直接把私有缓存的 `file://` 交给其它应用** — Android 会拒绝跨应用暴露 file URI，而且它会让任意应用可猜测或读取私有路径；受限副本加 `FileProvider` 只授予当前对象的读权限。
- **使用系统另存为或让 Go bridge 直接下载到内容 URI** — 用户不需要在 Android 预览中选择保存位置，bridge 的传输与缓存路径也以可写文件路径为契约；复用已校验缓存保持下载、预览和随后外部打开的单一实现。
- **自建轻量 Markdown 解析器** — 容易遗漏表格、代码块、任务列表、选择与链接行为；使用维护中的 Markdown 渲染包可提供完整 GitHub Flavored Markdown 表面。
- **让 Markdown 包按默认规则加载图片** — 远端对象中的图片 URI 不应获得网络或应用私有文件读取能力；统一无 I/O 占位保留文档结构，同时把外部资源访问留给明确点击的白名单链接。

## Consequences

- Android 用户可在预览内查看 Markdown、下载到应用缓存并选择其它应用打开文件；预览不提供系统另存为。
- 超过 8 MiB 的 Markdown 明确提示下载后查看；紧凑横屏和键盘高度下，预览 sheet 的标题、预览和动作可整体滚动。
- Markdown 图片不会自动请求网络或读取本地 URI，预览仅显示安全占位。
- 外部打开需要一次额外副本，副本只位于系统可清理的 cache 专用目录，超过一天的旧副本会在下一次打开时清理。
- 该原生交接边界只适用于 Android；桌面继续使用各平台 shell 与桌面文件选择器。

## Testing

Markdown 类型、8 MiB 上限、Android widget 渲染、Markdown 的远程/本地图片均不创建 image loader、缓存下载动作、48dp 触控/窄屏换行与横屏 + IME 可达性回归，以及 `flutter analyze`、Android `:app:compileDebugKotlin`、`go test ./...` 与 `make check-docs` 覆盖本次变更。
