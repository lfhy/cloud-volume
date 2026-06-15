// Object-path helpers keep CLI-visible paths aligned with the configured root prefix.
package main

import (
	"path/filepath"
	"strings"
)

func cleanObjectPath(value string) string {
	trimmed := strings.TrimSpace(value)
	trimmed = strings.ReplaceAll(trimmed, "\\", "/")
	trimmed = strings.Trim(trimmed, "/")
	if trimmed == "." {
		return ""
	}
	return trimmed
}

func ensureObjectDirSuffix(value string) string {
	clean := cleanObjectPath(value)
	if clean == "" {
		return ""
	}
	return clean + "/"
}

func applyRootPrefix(rootPrefix, visiblePath string, isDir bool) string {
	root := cleanObjectPath(rootPrefix)
	path := cleanObjectPath(visiblePath)
	if isDir {
		switch {
		case root == "" && path == "":
			return ""
		case root == "":
			return ensureObjectDirSuffix(path)
		case path == "":
			return ensureObjectDirSuffix(root)
		default:
			return ensureObjectDirSuffix(root + "/" + path)
		}
	}
	if root == "" {
		return path
	}
	if path == "" {
		return root
	}
	return root + "/" + path
}

func stripRootPrefix(rootPrefix, remotePath string, isDir bool) (string, bool) {
	root := cleanObjectPath(rootPrefix)
	remote := strings.Trim(strings.TrimSpace(strings.ReplaceAll(remotePath, "\\", "/")), "/")
	if root != "" {
		prefix := root + "/"
		switch {
		case remote == root:
			remote = ""
		case strings.HasPrefix(remote, prefix):
			remote = strings.TrimPrefix(remote, prefix)
		default:
			return "", false
		}
	}
	if isDir {
		return ensureObjectDirSuffix(remote), true
	}
	return cleanObjectPath(remote), true
}

func defaultDownloadPath(remotePath string) string {
	base := filepath.Base(cleanObjectPath(remotePath))
	if base == "." || base == "/" || base == "" {
		return "downloaded-object"
	}
	return base
}

func defaultRemoteObjectPath(localPath string) string {
	base := filepath.Base(strings.TrimSpace(localPath))
	if base == "." || base == string(filepath.Separator) || strings.TrimSpace(base) == "" {
		return ""
	}
	return cleanObjectPath(base)
}

func resolveVisiblePath(baseDir, value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return cleanObjectPath(baseDir)
	}
	normalized := strings.ReplaceAll(trimmed, "\\", "/")
	if strings.HasPrefix(normalized, "/") {
		return cleanObjectPath(normalized)
	}

	baseParts := splitObjectPath(baseDir)
	parts := splitObjectPath(normalized)
	stack := make([]string, 0, len(baseParts)+len(parts))
	stack = append(stack, baseParts...)
	for _, part := range parts {
		switch part {
		case "", ".":
			continue
		case "..":
			if len(stack) > 0 {
				stack = stack[:len(stack)-1]
			}
		default:
			stack = append(stack, part)
		}
	}
	return cleanObjectPath(strings.Join(stack, "/"))
}

func splitObjectPath(value string) []string {
	clean := cleanObjectPath(value)
	if clean == "" {
		return nil
	}
	return strings.Split(clean, "/")
}

func relativeListedPath(baseDir, value string, isDir bool) string {
	cleanBase := cleanObjectPath(baseDir)
	cleanValue := cleanObjectPath(value)
	if cleanBase != "" {
		prefix := cleanBase + "/"
		if cleanValue == cleanBase {
			cleanValue = ""
		} else if strings.HasPrefix(cleanValue, prefix) {
			cleanValue = strings.TrimPrefix(cleanValue, prefix)
		}
	}
	if isDir {
		return ensureObjectDirSuffix(cleanValue)
	}
	return cleanObjectPath(cleanValue)
}
