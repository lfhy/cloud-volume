//go:build windows && cgo

// Windows WinFsp backend hosts the cgofuse virtual file system on top of the
// existing bucketAccess read/write pipeline. Unlike Cloud Files it reports a
// real volume (drive letter + custom capacity) to Explorer, at the cost of
// requiring the WinFsp driver to be installed.
package mount

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/winfsp/cgofuse/fuse"

	storageconfig "remote-storage/go/config"
	storageops "remote-storage/go/storage"
)

const (
	// winFspBlockBytes is the granularity reported via Statfs; WinFsp/Explorer
	// render volume size from Blocks*Frsize, so keep them identical.
	winFspBlockBytes uint64 = 4096
)

type windowsWinFspBackend struct {
	cfg     storageconfig.RemoteStorageConfig
	host    *fuse.FileSystemHost
	fs      *winFspBucketFS
	doneCh  chan struct{}
	stopMu  sync.Mutex
	stopped bool
}

func newWindowsWinFspBackend(cfg storageconfig.RemoteStorageConfig) (mountBackend, error) {
	if !WindowsWinFspAvailable() {
		return nil, fmt.Errorf("WinFsp driver is not installed; install WinFsp from Settings or switch back to Cloud Files")
	}
	return &windowsWinFspBackend{cfg: cfg}, nil
}

func (b *windowsWinFspBackend) Initialize(session *mountSession) error {
	session.mountName = safeSegment(session.bucket)

	// WinFsp directory mounts fail for the virtual-volume configuration used by
	// this backend, so keep its contract explicitly drive-letter only.
	if err := validateWinFspDriveLetter(session.requestedDriveLetter); err != nil {
		return err
	}
	drive, err := selectWindowsDriveLetter(session.requestedDriveLetter)
	if err != nil {
		return err
	}
	session.mountPath = drive
	session.mountTarget = drive
	session.driveLetter = drive + `\`
	return nil
}

func (b *windowsWinFspBackend) Start(session *mountSession) error {
	defaultCapacityBytes := uint64(b.cfg.WindowsWinFspCapacityGB) * mountBytesPerGiB
	capacityBytes, usedBytes, capacitySource := b.resolveCapacity(session.bucket, defaultCapacityBytes)
	log.Printf(
		"[mount/winfsp] start bucket=%q path=%q capacity_bytes=%d used_bytes=%d capacity_source=%q read_only=%t",
		session.bucket,
		session.mountPath,
		capacityBytes,
		usedBytes,
		capacitySource,
		session.readOnly,
	)

	// Drive-letter mounts do not need a local directory; path mounts do.
	if !isWindowsDriveMount(session.mountPath) {
		if err := os.MkdirAll(session.mountPath, 0o755); err != nil {
			return fmt.Errorf("create winfsp mount path: %w", err)
		}
	}

	fs := newWinFspBucketFS(
		session.access,
		session.mountName,
		capacityBytes,
		usedBytes,
		session.readOnly,
	)
	host := fuse.NewFileSystemHost(fs)
	host.SetCapReaddirPlus(true)
	host.SetUseIno(true)

	b.fs = fs
	b.host = host
	b.doneCh = make(chan struct{})
	b.stopped = false

	// FileSystemHost.Mount blocks until the file system is unmounted, so run
	// it on its own goroutine and surface completion via doneCh.
	mountPath := session.mountPath
	volumeLabel := winFspVolumeLabel(b.cfg, session.bucket)
	go func() {
		defer close(b.doneCh)
		ok := host.Mount(mountPath, winFspMountOptions(volumeLabel))
		log.Printf("[mount/winfsp] host-exited bucket=%q ok=%t", session.bucket, ok)
	}()

	if err := b.waitUntilActive(session, 8*time.Second); err != nil {
		_ = b.stopHost()
		return err
	}

	session.mounted = true
	log.Printf("[mount/winfsp] start-done bucket=%q path=%q", session.bucket, session.mountPath)
	return nil
}

// resolveCapacity keeps an unavailable provider quota from blocking a mount,
// while using the provider's total and used values whenever it reports them.
func (b *windowsWinFspBackend) resolveCapacity(bucket string, fallback uint64) (uint64, uint64, string) {
	if b.cfg.BucketSettingsFor(bucket).CustomQuotaBytes > 0 {
		capacity, used := resolvedMountCapacity(b.cfg, bucket, 0, 0, fallback)
		return capacity, used, "bucket_custom"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	providerQuota, err := storageops.GetBucketQuota(ctx, b.cfg, bucket)
	if err != nil {
		log.Printf("[mount/winfsp] quota lookup failed bucket=%q error=%v", bucket, err)
	} else if providerQuota.QuotaBytes > 0 {
		capacity, used := resolvedMountCapacity(
			b.cfg,
			bucket,
			providerQuota.QuotaBytes,
			providerQuota.UsedBytes,
			fallback,
		)
		return capacity, used, "provider"
	}

	capacity, used := resolvedMountCapacity(b.cfg, bucket, 0, 0, fallback)
	return capacity, used, "windows_default"
}

func (b *windowsWinFspBackend) Stop(session *mountSession) error {
	log.Printf("[mount/winfsp] stop bucket=%q path=%q", session.bucket, session.mountPath)
	session.mounted = false

	var firstErr error
	if stopErr := b.stopHost(); stopErr != nil {
		firstErr = stopErr
	}
	// When we mounted onto a drive letter directly, WinFsp unmount clears it.
	// Only clear the session field; do not call subst /D.
	if session.driveLetter != "" && isWindowsDriveMount(session.mountPath) {
		session.driveLetter = ""
	} else if session.driveLetter != "" {
		if err := removeWindowsDriveLetter(session.driveLetter, session.mountPath); err != nil && firstErr == nil {
			firstErr = err
		} else {
			session.driveLetter = ""
		}
	}
	if session.access != nil {
		if err := session.access.drainWriteback(); err != nil && firstErr == nil {
			firstErr = err
		}
		session.access.release()
		_ = session.access.close()
	}
	b.fs = nil
	b.host = nil
	if firstErr != nil {
		log.Printf("[mount/winfsp] stop-error bucket=%q error=%v", session.bucket, firstErr)
		return firstErr
	}
	log.Printf("[mount/winfsp] stop-done bucket=%q", session.bucket)
	return nil
}

func (b *windowsWinFspBackend) IsActive(session *mountSession) (bool, error) {
	if b.host == nil {
		return false, nil
	}
	// A zero-length readdir on the mount path is the most reliable liveness
	// probe; cgofuse has no public "mounted" flag on Windows.
	_, err := os.ReadDir(session.mountPath)
	if err != nil {
		return false, nil
	}
	return true, nil
}

func (b *windowsWinFspBackend) CleanupStale(session *mountSession) error {
	if isWindowsDriveMount(session.mountPath) {
		return nil
	}
	if err := cleanupWindowsDriveMappingsForPath(session.mountPath); err != nil {
		return err
	}
	if _, err := os.Stat(session.mountPath); os.IsNotExist(err) {
		return nil
	}
	return os.RemoveAll(session.mountPath)
}

// waitUntilActive polls IsActive until the WinFsp host is serving or the
// deadline expires. The host goroutine may still be finishing Mount when we
// return from Start.
func (b *windowsWinFspBackend) waitUntilActive(session *mountSession, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		select {
		case <-b.doneCh:
			return fmt.Errorf("WinFsp mount exited before becoming active for %q", session.mountPath)
		default:
		}
		ready, err := b.IsActive(session)
		if err != nil {
			return err
		}
		if ready {
			return nil
		}
		time.Sleep(150 * time.Millisecond)
	}
	return fmt.Errorf("WinFsp mount did not become active for %q", session.mountPath)
}

// winFspMountOptions keeps the FUSE volume geometry aligned with Statfs so
// Explorer calculates total and free space from the same 4096-byte unit.
func winFspMountOptions(volumeLabel string) []string {
	return []string{
		"-o", "volname=" + volumeLabel,
		"-o", "FileSystemName=CloudVolume",
		"-o", "SectorSize=4096",
		"-o", "SectorsPerAllocationUnit=1",
	}
}

// stopHost unmounts the cgofuse host exactly once and waits for the serving
// goroutine to exit so Stop never races a second invocation.
func (b *windowsWinFspBackend) stopHost() error {
	b.stopMu.Lock()
	defer b.stopMu.Unlock()
	if b.stopped || b.host == nil {
		b.stopped = true
		return nil
	}
	b.stopped = true
	host := b.host
	unmounted := host.Unmount()
	if b.doneCh != nil {
		<-b.doneCh
	}
	if !unmounted {
		return fmt.Errorf("winfsp unmount failed")
	}
	return nil
}

// cleanupManagedWindowsWinFspArtifacts removes leftover WinFsp mount
// directories under the managed root during full shutdown/cleanup.
func cleanupManagedWindowsWinFspArtifacts() error {
	rootPath, err := windowsCloudFilesRootPath()
	if err != nil {
		return err
	}
	entries, err := os.ReadDir(rootPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		if !hasWinFspMountSuffix(entry.Name()) {
			continue
		}
		localPath := filepath.Join(rootPath, entry.Name())
		if err := os.RemoveAll(localPath); err != nil {
			log.Printf("[mount/winfsp] cleanup-remove path=%q error=%v", localPath, err)
			continue
		}
		log.Printf("[mount/winfsp] cleanup-remove path=%q", localPath)
	}
	return nil
}
