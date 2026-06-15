// Mount helpers normalize virtual paths and cache-safe filesystem names.
package mount

import (
	"os"
	"path/filepath"
	"strings"

	s3ops "remote-storage/go/s3"
)

func cloneObjects(items []s3ops.ObjectInfo) []s3ops.ObjectInfo {
	if len(items) == 0 {
		return []s3ops.ObjectInfo{}
	}
	out := make([]s3ops.ObjectInfo, len(items))
	copy(out, items)
	return out
}

func cleanVirtualPath(value string) string {
	trimmed := strings.Trim(strings.TrimSpace(value), "/")
	if trimmed == "." {
		return ""
	}
	return trimmed
}

func ensureDirSuffix(value string) string {
	trimmed := strings.TrimSuffix(strings.TrimSpace(value), "/")
	if trimmed == "" {
		return ""
	}
	return trimmed + "/"
}

func parentVirtualPrefix(virtualPath string) string {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return ""
	}
	index := strings.LastIndex(clean, "/")
	if index < 0 {
		return ""
	}
	return clean[:index]
}

func baseName(virtualPath string) string {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return ""
	}
	parts := strings.Split(clean, "/")
	return parts[len(parts)-1]
}

func isLocalMetadataPath(virtualPath string) bool {
	name := baseName(virtualPath)
	if name == "" {
		return false
	}
	if strings.HasPrefix(name, "._") {
		return true
	}
	switch name {
	case ".DS_Store", ".localized":
		return true
	default:
		return false
	}
}

func isEphemeralMountFilePath(virtualPath string) bool {
	name := strings.ToLower(filepath.Base(cleanVirtualPath(virtualPath)))
	if name == "" {
		return false
	}
	if strings.HasPrefix(name, "~$") {
		return true
	}
	if strings.HasPrefix(name, "~wrl") && strings.HasSuffix(name, ".tmp") {
		return true
	}
	switch {
	case strings.HasPrefix(name, "~wr") && strings.HasSuffix(name, ".tmp"):
		return true
	case strings.HasPrefix(name, "~df") && strings.HasSuffix(name, ".tmp"):
		return true
	default:
		return false
	}
}

func splitVirtualPath(virtualPath string) []string {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return nil
	}
	return strings.Split(clean, "/")
}

func safeSegment(value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return "_"
	}
	return strings.NewReplacer("/", "_", "\\", "_", ":", "_").Replace(trimmed)
}

func isUsableLocalFile(localPath string, expectedSize int64) bool {
	info, err := os.Stat(localPath)
	if err != nil || info.IsDir() {
		return false
	}
	if expectedSize > 0 && info.Size() != expectedSize {
		return false
	}
	return true
}
