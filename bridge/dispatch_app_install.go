// Bridge method for in-app update: download + install + relaunch.
//
// All platform-specific logic is handled here so Flutter only renders UI and
// polls progress through the existing TransferQueue polling loop.
//
// Supported platforms:
//   - macOS:  DMG (hdiutil attach → cp → detach → xattr) or ZIP (unzip)
//   - Windows: Inno Setup .exe installer or ZIP green-package replacement
//   - Linux:   .AppImage (self-replace) or .tar.gz (extract to install dir)

package main

import (
	"archive/zip"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

type appInstallArgs struct {
	AssetURL      string                            `json:"assetUrl"`
	AssetName     string                            `json:"assetName"`
	AssetSize     int64                             `json:"assetSize"`
	AssetDigest   string                            `json:"assetDigest"`
	InstallerType string                            `json:"installerType"`
	MirrorPrefix  string                            `json:"mirrorPrefix"`
	Config        storageconfig.RemoteStorageConfig `json:"config"`
	ProxyMode     string                            `json:"proxyMode"`
	ProxyType     string                            `json:"proxyType"`
	ProxyHost     string                            `json:"proxyHost"`
	ProxyPort     string                            `json:"proxyPort"`
	ProxyUsername string                            `json:"proxyUsername"`
	ProxyPassword string                            `json:"proxyPassword"`
}

type appInstallResult struct {
	TaskID string `json:"taskId"`
}

func installApp(args json.RawMessage) (any, error) {
	var input appInstallArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if input.AssetURL == "" {
		return nil, fmt.Errorf("missing asset URL")
	}
	if input.AssetName == "" {
		return nil, fmt.Errorf("missing asset name")
	}

	taskID := fmt.Sprintf("app_update_%d", time.Now().UnixMilli())
	ctx, cancel := context.WithCancel(context.Background())

	// Register with transfer monitor so Flutter can poll progress.
	s3ops.QueueTransfer(taskID, "app_update", "", input.AssetName, "", 0)

	go runAppUpdateInstall(ctx, cancel, taskID, input)

	return appInstallResult{TaskID: taskID}, nil
}

// runAppUpdateInstall runs the full download + install + relaunch sequence in a
// background goroutine. It updates the transfer monitor at each stage so Flutter
// can reflect progress. On success it calls os.Exit(0) after spawning the new
// binary. On failure it marks the task as failed and returns.
func runAppUpdateInstall(ctx context.Context, cancel context.CancelFunc, taskID string, input appInstallArgs) {
	defer cancel()

	// Keep the asset name in the logical key so the unified task projection can
	// render it; localPath is reserved for the downloaded cache file.
	s3ops.StartQueuedTransfer(taskID, "app_update", "", input.AssetName, "", 0, cancel)
	s3ops.SetTransferStatusDetail(taskID, "downloading")

	// Build the download URL with optional mirror prefix.
	downloadURL := input.AssetURL
	if input.MirrorPrefix != "" {
		prefix := strings.TrimRight(input.MirrorPrefix, "/")
		downloadURL = prefix + "/" + input.AssetURL
	}

	// Build proxy-aware HTTP client using the config package.
	proxyCfg := storageconfig.RemoteStorageConfig{
		ProxyMode:     input.ProxyMode,
		ProxyType:     input.ProxyType,
		ProxyHost:     input.ProxyHost,
		ProxyPort:     input.ProxyPort,
		ProxyUsername: input.ProxyUsername,
		ProxyPassword: input.ProxyPassword,
	}
	// Install packages are large; a 120s whole-request timeout caused frequent
	// mid-download failures on slow links or mirrors. Allow up to two hours.
	httpClient := storageconfig.ProxyHTTPClient(proxyCfg, 7200)

	// Some mirrors silently return 403/HTML for large releases; probe the
	// wrapped URL with a quick HEAD so we can fail fast with a clear message
	// and let the user switch mirrors rather than watching 0 bytes forever.
	if input.MirrorPrefix != "" {
		probeClient := storageconfig.ProxyHTTPClient(proxyCfg, 20)
		if err := probeDownloadURL(probeClient, downloadURL, input.AssetSize); err != nil {
			finishTransferError(taskID, fmt.Sprintf("镜像不可用：%v", err))
			return
		}
	}

	dlPath, err := resolveInstallerDestPath(input.Config, input.AssetName)
	if err != nil {
		finishTransferError(taskID, fmt.Sprintf("准备更新缓存目录失败：%v", err))
		return
	}

	if err := downloadInstaller(ctx, httpClient, taskID, downloadURL, dlPath, input.AssetDigest, input.AssetSize); err != nil {
		finishTransferError(taskID, fmt.Sprintf("下载失败：%v", err))
		return
	}

	s3ops.SetTransferStatusDetail(taskID, "installing")
	// Installer processes have crossed the reversible boundary. The update
	// task remains visible, but cancellation must no longer be advertised.
	s3ops.SetTransferCancelable(taskID, false)

	// Platform-specific install.
	switch runtime.GOOS {
	case "darwin":
		if err := installMacOS(taskID, dlPath, input.InstallerType); err != nil {
			finishTransferError(taskID, fmt.Sprintf("macOS 安装失败：%v", err))
			return
		}
	case "windows":
		if err := installWindows(taskID, dlPath, input.InstallerType); err != nil {
			finishTransferError(taskID, fmt.Sprintf("Windows 安装失败：%v", err))
			return
		}
	case "linux":
		if err := installLinux(taskID, dlPath, input.InstallerType); err != nil {
			finishTransferError(taskID, fmt.Sprintf("Linux 安装失败：%v", err))
			return
		}
	default:
		finishTransferError(taskID, fmt.Sprintf("不支持的平台：%s", runtime.GOOS))
		return
	}

	// Install succeeded - mark done and relaunch.
	s3ops.FinishQueuedTransfer(taskID, nil)
	// Short delay so Flutter polling can read the "done" status before we exit.
	time.Sleep(500 * time.Millisecond)

	// Relaunch and exit.
	relaunchApp()
	time.Sleep(800 * time.Millisecond)
	os.Exit(0)
}

// installMacOS handles DMG or ZIP installation on macOS.
func installMacOS(taskID, dlPath, installerType string) error {
	if _, err := os.Stat(dlPath); os.IsNotExist(err) {
		return fmt.Errorf("安装包不存在：%s", dlPath)
	}

	appName := "云卷.app"
	appsDir := "/Applications"
	targetApp := filepath.Join(appsDir, appName)

	switch installerType {
	case "dmg":
		return installMacOSDMG(dlPath, appName, appsDir, targetApp)
	default:
		return installMacOSZip(dlPath, appName, appsDir, targetApp)
	}
}

func installMacOSDMG(dlPath, appName, appsDir, targetApp string) error {
	// Mount the DMG. Use -plist for machine-readable output.
	out, err := exec.Command("hdiutil", "attach", "-nobrowse", "-noautoopen", "-plist", dlPath).CombinedOutput()
	if err != nil {
		return fmt.Errorf("挂载 DMG 失败：%s（%v）", strings.TrimSpace(string(out)), err)
	}

	// Parse the mount point from the plist output.
	mountPoint := parseMountPointFromPlist(string(out))
	if mountPoint == "" {
		// Fallback: scan /Volumes for the newly added volume.
		mountPoint, _ = findNewMountPoint()
	}
	if mountPoint == "" {
		exec.Command("hdiutil", "detach", dlPath, "-quiet").Run()
		return fmt.Errorf("无法确定 DMG 挂载点")
	}

	mountedApp := filepath.Join(mountPoint, appName)
	if _, err := os.Stat(mountedApp); os.IsNotExist(err) {
		exec.Command("hdiutil", "detach", mountPoint, "-quiet").Run()
		return fmt.Errorf("DMG 内未找到 %s", appName)
	}

	// Remove old app if it exists.
	if _, err := os.Stat(targetApp); err == nil {
		if err := os.RemoveAll(targetApp); err != nil {
			exec.Command("hdiutil", "detach", mountPoint, "-quiet").Run()
			return fmt.Errorf("删除旧应用失败：%w", err)
		}
	}

	// Copy new app.
	copyOut, copyErr := exec.Command("cp", "-R", mountedApp, appsDir).CombinedOutput()
	detachOut, detachErr := exec.Command("hdiutil", "detach", mountPoint, "-quiet").CombinedOutput()
	if detachErr != nil {
		log.Printf("[app_install] detach warning: %s", strings.TrimSpace(string(detachOut)))
	}
	if copyErr != nil {
		return fmt.Errorf("复制应用失败：%s（%v）", strings.TrimSpace(string(copyOut)), copyErr)
	}

	// Strip quarantine.
	exec.Command("xattr", "-cr", targetApp).Run()

	return nil
}

func installMacOSZip(dlPath, appName, appsDir, targetApp string) error {
	// Remove old app if it exists.
	if _, err := os.Stat(targetApp); err == nil {
		if err := os.RemoveAll(targetApp); err != nil {
			return fmt.Errorf("删除旧应用失败：%w", err)
		}
	}

	out, err := exec.Command("unzip", "-o", dlPath, "-d", appsDir).CombinedOutput()
	if err != nil {
		return fmt.Errorf("解压失败：%s（%v）", strings.TrimSpace(string(out)), err)
	}

	// Strip quarantine.
	exec.Command("xattr", "-cr", targetApp).Run()

	return nil
}

// parseMountPointFromPlist extracts the mount point from hdiutil -plist output.
// The plist contains a "mount-point" key under each system-entities entry.
func parseMountPointFromPlist(plist string) string {
	// The plist contains <key>mount-point</key> followed by a <string> value.
	// Whitespace/newlines vary, so scan in two steps instead of matching both tags.
	key := "<key>mount-point</key>"
	idx := strings.Index(plist, key)
	if idx < 0 {
		return ""
	}
	remaining := plist[idx+len(key):]
	startTag := "<string>"
	startIdx := strings.Index(remaining, startTag)
	if startIdx < 0 {
		return ""
	}
	start := startIdx + len(startTag)
	end := strings.Index(remaining[start:], "</string>")
	if end < 0 {
		return ""
	}
	return remaining[start : start+end]
}

// findNewMountPoint scans /Volumes to find a non-standard volume.
// Called as fallback when plist parsing fails.
func findNewMountPoint() (string, error) {
	knownVolumes := map[string]bool{
		"Macintosh HD": true,
		"Recovery":     true,
		"Update":       true,
		"Preboot":      true,
		"VM":           true,
	}

	entries, err := os.ReadDir("/Volumes")
	if err != nil {
		return "", fmt.Errorf("读取 /Volumes 失败：%w", err)
	}

	for _, entry := range entries {
		name := entry.Name()
		if !knownVolumes[name] && entry.IsDir() {
			return filepath.Join("/Volumes", name), nil
		}
	}

	return "", nil
}

// installWindows handles EXE or ZIP installation on Windows.
func installWindows(taskID, dlPath, installerType string) error {
	switch installerType {
	case "exe":
		cmd := exec.Command(dlPath, "/SILENT", "/CLOSEAPPLICATIONS", "/NORESTART", "/SP-", "/NOCANCEL")
		if err := cmd.Start(); err != nil {
			return fmt.Errorf("启动安装程序失败：%w", err)
		}
		time.Sleep(500 * time.Millisecond)
		return nil
	case "zip":
		return installWindowsZip(dlPath)
	default:
		return fmt.Errorf("请使用 installer (.exe) 版本进行自动更新")
	}
}

func installWindowsZip(dlPath string) error {
	if _, err := os.Stat(dlPath); err != nil {
		return fmt.Errorf("update package not found: %s", dlPath)
	}
	currentExe, err := os.Executable()
	if err != nil {
		return fmt.Errorf("resolve current executable: %w", err)
	}
	installDir := filepath.Dir(currentExe)
	relaunchExe := appRelaunchExecutable(currentExe)

	// Prefer the updater EXE already in the install directory (shipped with
	// the current build). If it's missing (old version pre-updater), fall back
	// to extracting it from the downloaded zip into a temp file.
	updaterPath := filepath.Join(installDir, "cloud-volume-updater.exe")
	if _, err := os.Stat(updaterPath); err != nil {
		updaterPath, err = extractUpdaterFromZip(dlPath)
		if err != nil {
			return fmt.Errorf("updater not found and extract from zip failed: %w", err)
		}
	}
	cmd := exec.Command(updaterPath,
		"-zip", dlPath,
		"-install-dir", installDir,
		"-pid", fmt.Sprintf("%d", os.Getpid()),
		"-exe-name", filepath.Base(relaunchExe),
	)
	cmd.SysProcAttr = windowsHiddenProcessAttrs()
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start updater: %w", err)
	}
	// Log the updater invocation so failures are traceable in bridge.log. The
	// updater itself writes a detailed per-step log to %TEMP%\cloud-volume-updater-<pid>.log.
	log.Printf("[app_install] spawned updater: %s pid=%d install-dir=%s zip=%s",
		updaterPath, cmd.Process.Pid, installDir, dlPath)
	time.Sleep(500 * time.Millisecond)
	return nil
}

// extractUpdaterFromZip opens the release zip, finds cloud-volume-updater.exe
// at the root or in a subdirectory, and copies it to a temp file.
func extractUpdaterFromZip(zipPath string) (string, error) {
	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return "", err
	}
	defer r.Close()
	const updaterName = "cloud-volume-updater.exe"
	for _, f := range r.File {
		base := filepath.Base(f.Name)
		if !strings.EqualFold(base, updaterName) || f.FileInfo().IsDir() {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			return "", err
		}
		defer rc.Close()
		tmp, err := os.CreateTemp("", "cloud-volume-updater-*.exe")
		if err != nil {
			return "", err
		}
		if _, err := io.Copy(tmp, rc); err != nil {
			tmp.Close()
			return "", err
		}
		tmp.Close()
		return tmp.Name(), nil
	}
	return "", fmt.Errorf("%s not found in the update package", updaterName)
}

// installLinux handles AppImage or tarball installation on Linux.
func installLinux(taskID, dlPath, installerType string) error {
	switch installerType {
	case "appimage":
		currentExe, err := os.Executable()
		if err != nil {
			return fmt.Errorf("获取当前可执行路径失败：%w", err)
		}
		targetPath := currentExe

		input, err := os.ReadFile(dlPath)
		if err != nil {
			return fmt.Errorf("读取安装包失败：%w", err)
		}
		if err := os.WriteFile(targetPath, input, 0755); err != nil {
			return fmt.Errorf("替换应用失败：%w", err)
		}
		return nil

	default:
		// tarball
		currentExe, err := os.Executable()
		if err != nil {
			return fmt.Errorf("获取当前可执行路径失败：%w", err)
		}
		installDir := filepath.Dir(currentExe)

		out, err := exec.Command("tar", "-xzf", dlPath, "--strip-components=1", "-C", installDir).CombinedOutput()
		if err != nil {
			return fmt.Errorf("解压失败：%s（%v）", strings.TrimSpace(string(out)), err)
		}
		return nil
	}
}

// relaunchApp starts the newly installed application.
func relaunchApp() {
	switch runtime.GOOS {
	case "darwin":
		// Launch via the .app bundle so LaunchServices owns the new process;
		// spawning the raw binary directly surfaces a foreground shell-style
		// process without normal window/activation lifecycle.
		_ = exec.Command("open", "-n", "/Applications/云卷.app").Start()
	case "windows":
		// The installer handles relaunch; just exit.
	case "linux":
		currentExe, err := os.Executable()
		if err == nil {
			exec.Command(currentExe).Start()
		}
	}
}

// finishTransferError marks the transfer task as failed with an error message.
func finishTransferError(taskID, msg string) {
	log.Printf("[app_install] %s: %s", taskID, msg)
	s3ops.FinishQueuedTransfer(taskID, fmt.Errorf("%s", msg))
}

// probeDownloadURL sends a short HEAD request to verify a mirror is actually
// serving the release asset. Many public mirrors return 403/HTML for large
// GitHub release downloads or drop the Range header; failing fast here beats a
// silent 0-byte download that looks like a stuck progress bar.
//
// When expectedSize > 0 we also compare the mirror's reported Content-Length
// against it. Some mirrors answer HEAD 200 with a bogus/small Content-Length
// (or omit it) while GET would serve a truncated payload; flagging the mismatch
// here steers the user toward a working mirror before a corrupt download.
func probeDownloadURL(client *http.Client, url string, expectedSize int64) error {
	req, err := http.NewRequest("HEAD", url, nil)
	if err != nil {
		return fmt.Errorf("构造探测请求失败：%w", err)
	}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("探测镜像失败：%w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("镜像返回 HTTP %d", resp.StatusCode)
	}
	if expectedSize > 0 {
		// A server may legitimately not know the length (chunked transfer) and
		// report -1; only reject when it advertises a concrete, wrong length.
		if resp.ContentLength > 0 && resp.ContentLength != expectedSize {
			return fmt.Errorf(
				"镜像报称大小为 %d 字节，与 GitHub Release 的 %d 字节不一致",
				resp.ContentLength, expectedSize,
			)
		}
	}
	return nil
}
