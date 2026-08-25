// Package mount owns bucket-to-desktop mount lifecycle and WebDAV-facing models.
package mount

import (
	"strings"
	"time"

	storageconfig "remote-storage/go/config"
)

const (
	defaultRequestTimeout  = 15
	defaultTransferTimeout = 300
	defaultCacheTTL        = 15
	defaultPrefetchTTL     = 10
	mountProbeCacheTTL     = 1200 * time.Millisecond
)

// BucketMountStatus is returned to Flutter so the UI can render mount actions.
type BucketMountStatus struct {
	Mounted     bool   `json:"mounted"`
	Bucket      string `json:"bucket"`
	MountPath   string `json:"mountPath"`
	ServerURL   string `json:"serverUrl"`
	Port        int    `json:"port"`
	DriveLetter string `json:"driveLetter,omitempty"`
	LastError   string `json:"lastError,omitempty"`
}

// mountBackend keeps lifecycle differences out of the cross-platform manager.
type mountBackend interface {
	Initialize(*mountSession) error
	Start(*mountSession) error
	Stop(*mountSession) error
	IsActive(*mountSession) (bool, error)
	CleanupStale(*mountSession) error
}

type mountProbeSnapshot struct {
	checkedAt time.Time
	active    bool
	err       error
}

type mountSession struct {
	config               storageconfig.RemoteStorageConfig
	bucket               string
	rootPrefix           string
	mountName            string
	requestedPath        string
	readOnly             bool
	removeLocalCache     bool
	requestedDriveLetter string
	autoSync             bool
	uploadWorkers        int
	mountPath            string
	mountTarget          string
	driveLetter          string
	managedPath          bool
	serverURL            string
	port                 int
	mounted              bool
	mountAttempted       bool
	server               *webDAVServer
	access               *bucketAccess
	backend              mountBackend
	remotePoller         *remoteDirectoryPoller
	lastError            string
	stopping             bool
}

func (s *mountSession) status() BucketMountStatus {
	if s == nil {
		return BucketMountStatus{}
	}
	errors := make([]string, 0, 3)
	if message := strings.TrimSpace(s.lastError); message != "" {
		errors = append(errors, message)
	}
	if s.access != nil && s.access.writeback != nil {
		if message := strings.TrimSpace(s.access.writeback.mutationLastError()); message != "" {
			errors = append(errors, message)
		}
	}
	if s.access != nil && s.access.dirSync != nil {
		if message := strings.TrimSpace(s.access.dirSync.lastError()); message != "" {
			errors = append(errors, message)
		}
	}
	lastError := strings.Join(errors, "\n")
	return BucketMountStatus{
		Mounted:     s.mounted,
		Bucket:      s.bucket,
		MountPath:   s.mountPath,
		ServerURL:   s.serverURL,
		Port:        s.port,
		DriveLetter: s.driveLetter,
		LastError:   lastError,
	}
}

func normalizeRootPrefix(value string) string {
	return strings.Trim(strings.TrimSpace(value), "/")
}
