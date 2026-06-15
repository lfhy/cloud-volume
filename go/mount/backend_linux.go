//go:build linux

// Linux mount lifecycle keeps the cross-platform bucket manager wired to FUSE.
package mount

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	gofusefs "github.com/hanwen/go-fuse/v2/fs"
	"github.com/hanwen/go-fuse/v2/fuse"

	storageconfig "remote-storage/go/config"
)

const (
	linuxFuseAttrTTL       = time.Second
	linuxFuseMaxBackground = 64
	linuxFuseMaxWrite      = 1 << 20
	linuxFuseMaxReadAhead  = 1 << 20
)

type linuxFUSEBackend struct {
	server *fuse.Server
}

func newPlatformMountBackend(_ storageconfig.RemoteStorageConfig) (mountBackend, error) {
	return &linuxFUSEBackend{}, nil
}

func (b *linuxFUSEBackend) Initialize(session *mountSession) error {
	session.mountName = safeSegment(session.bucket)
	mountPath := normalizeMountPath(session.requestedPath)
	if mountPath == "" {
		defaultPath, err := linuxMountPath(session.bucket)
		if err != nil {
			return err
		}
		session.managedPath = true
		mountPath = defaultPath
	}
	session.mountPath = mountPath
	session.mountTarget = mountPath
	return nil
}

func (b *linuxFUSEBackend) Start(session *mountSession) error {
	log.Printf("[mount/linux] start bucket=%q mount_path=%q", session.bucket, session.mountPath)
	if err := prepareLinuxMountPath(session.mountPath, session.managedPath); err != nil {
		return fmt.Errorf("create linux mount path: %w", err)
	}

	root := newLinuxFuseNode(session.access, true)
	server, err := gofusefs.Mount(session.mountPath, root, &gofusefs.Options{
		EntryTimeout: ptrDuration(linuxFuseAttrTTL),
		AttrTimeout:  ptrDuration(linuxFuseAttrTTL),
		MountOptions: fuse.MountOptions{
			Name:              "cloud-volume",
			FsName:            "cloud-volume:" + session.bucket,
			DisableXAttrs:     true,
			MaxBackground:     linuxFuseMaxBackground,
			MaxWrite:          linuxFuseMaxWrite,
			MaxReadAhead:      linuxFuseMaxReadAhead,
			ExtraCapabilities: fuse.CAP_WRITEBACK_CACHE,
			Options:           []string{"default_permissions"},
		},
	})
	if err != nil {
		log.Printf("[mount/linux] mount-error bucket=%q mount_path=%q error=%v", session.bucket, session.mountPath, err)
		return fmt.Errorf("mount bucket with linux fuse: %w", err)
	}

	b.server = server
	session.mounted = true
	log.Printf("[mount/linux] start-done bucket=%q mount_path=%q", session.bucket, session.mountPath)
	return nil
}

func (b *linuxFUSEBackend) Stop(session *mountSession) error {
	log.Printf("[mount/linux] stop bucket=%q mount_path=%q", session.bucket, session.mountPath)
	session.mounted = false

	var firstErr error
	if session.access != nil {
		log.Printf("[mount/linux] drain-start bucket=%q mount_path=%q", session.bucket, session.mountPath)
		if err := session.access.drainWriteback(); err != nil && firstErr == nil {
			firstErr = fmt.Errorf("drain linux writeback: %w", err)
		}
		if firstErr != nil {
			log.Printf("[mount/linux] drain-error bucket=%q mount_path=%q error=%v", session.bucket, session.mountPath, firstErr)
		} else {
			log.Printf("[mount/linux] drain-done bucket=%q mount_path=%q", session.bucket, session.mountPath)
		}
	}
	if b.server != nil {
		if err := b.server.Unmount(); err != nil && firstErr == nil {
			firstErr = fmt.Errorf("unmount linux fuse: %w", err)
		}
		b.server = nil
	} else if active, err := linuxMountActive(session.mountPath); err == nil && active {
		if err := linuxUnmountPath(session.mountPath); err != nil && firstErr == nil {
			firstErr = err
		}
	}

	if err := session.access.close(); err != nil && firstErr == nil {
		firstErr = err
	}
	if session.managedPath {
		if err := os.RemoveAll(session.mountPath); err != nil && !os.IsNotExist(err) && firstErr == nil {
			firstErr = err
		}
	} else if err := os.MkdirAll(filepath.Clean(session.mountPath), 0o755); err != nil && firstErr == nil {
		firstErr = err
	}
	if firstErr != nil {
		log.Printf("[mount/linux] stop-error bucket=%q mount_path=%q error=%v", session.bucket, session.mountPath, firstErr)
	} else {
		log.Printf("[mount/linux] stop-done bucket=%q mount_path=%q", session.bucket, session.mountPath)
	}
	return firstErr
}

func (b *linuxFUSEBackend) IsActive(session *mountSession) (bool, error) {
	return linuxMountActive(session.mountPath)
}

func (b *linuxFUSEBackend) CleanupStale(session *mountSession) error {
	active, err := linuxMountActive(session.mountPath)
	if err != nil {
		return err
	}
	if active {
		if err := linuxUnmountPath(session.mountPath); err != nil {
			return err
		}
	}
	if session.managedPath {
		if err := os.RemoveAll(session.mountPath); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	return nil
}

func cleanupAllManagedMounts() error {
	paths, err := listLinuxManagedMountPaths()
	if err != nil {
		return err
	}
	for _, mountPath := range paths {
		if err := linuxUnmountPath(mountPath); err != nil {
			return err
		}
		_ = os.RemoveAll(mountPath)
	}
	return nil
}

func ptrDuration(value time.Duration) *time.Duration {
	return &value
}
