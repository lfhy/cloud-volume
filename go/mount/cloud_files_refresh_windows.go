//go:build windows && cgo

// Cloud Files refresh projects remote poll changes into existing sync-root entries.
package mount

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	s3ops "remote-storage/go/s3"
)

// RefreshPlaceholders applies a remote poll to an opened directory. New entries
// become placeholders, changed files lose hydrated content, and remote removals
// disappear locally unless a local writeback still owns that path.
func (h *cloudFilesHydrator) RefreshPlaceholders(
	virtualPrefix string,
	items []s3ops.ObjectInfo,
) error {
	if h == nil || h.provider == nil || h.watcher == nil || h.access == nil {
		return nil
	}
	placeholders := cloudFilesDirectoryPlaceholders(items)
	return h.refreshPlaceholders(virtualPrefix, placeholders)
}

// RefreshMetadataPlaceholders retains metadata OIDs as Cloud Files identities
// while using a separate fingerprint to keep same-size overwrites dehydrated.
func (h *cloudFilesHydrator) RefreshMetadataPlaceholders(
	virtualPrefix string,
	items []metadataMountObject,
) error {
	if h == nil || h.provider == nil || h.watcher == nil || h.access == nil {
		return nil
	}
	return h.refreshPlaceholders(
		virtualPrefix,
		cloudFilesMetadataDirectoryPlaceholders(items, h.access.metadataNamespaceID()),
	)
}

func (h *cloudFilesHydrator) refreshPlaceholders(
	virtualPrefix string,
	placeholders []cloudPlaceholderInfo,
) error {
	localPath := cloudFilesVirtualPathToLocal(h.syncRoot, virtualPrefix)
	if virtualPrefix == "" {
		localPath = h.syncRoot
	}
	if err := h.refreshProjectedDirectory(localPath, placeholders); err != nil {
		return err
	}
	log.Printf(
		"[mount/cloud-files] poll-placeholders virtual=%q count=%d",
		virtualPrefix,
		len(placeholders),
	)
	return nil
}

func cloudFilesDirectoryPlaceholders(items []s3ops.ObjectInfo) []cloudPlaceholderInfo {
	placeholders := make([]cloudPlaceholderInfo, 0, len(items))
	for _, item := range items {
		relativeName := strings.TrimSuffix(baseName(item.Key), "/")
		if relativeName == "" {
			continue
		}
		placeholder := cloudFilesPlaceholderInfo(item)
		placeholder.RelativePath = relativeName
		placeholders = append(placeholders, placeholder)
	}
	return placeholders
}

func cloudFilesMetadataDirectoryPlaceholders(
	items []metadataMountObject,
	namespace string,
) []cloudPlaceholderInfo {
	placeholders := make([]cloudPlaceholderInfo, 0, len(items))
	for _, item := range items {
		relativeName := strings.TrimSuffix(baseName(item.info.Key), "/")
		if relativeName == "" {
			continue
		}
		placeholder := cloudFilesMetadataPlaceholderInfo(item, namespace)
		placeholder.RelativePath = relativeName
		placeholders = append(placeholders, placeholder)
	}
	return placeholders
}

func (h *cloudFilesHydrator) rememberProjectedDirectory(
	localPath string,
	items []cloudPlaceholderInfo,
) {
	if h == nil {
		return
	}
	h.projectionMu.Lock()
	defer h.projectionMu.Unlock()
	if h.projectedDirectories == nil {
		h.projectedDirectories = map[string]map[string]cloudPlaceholderInfo{}
	}
	h.projectedDirectories[filepath.Clean(localPath)] = cloudFilesPlaceholderMap(items)
}

func (h *cloudFilesHydrator) hasProjectedDirectory(localPath string) bool {
	if h == nil {
		return false
	}
	h.projectionMu.Lock()
	defer h.projectionMu.Unlock()
	_, ok := h.projectedDirectories[filepath.Clean(localPath)]
	return ok
}

func (h *cloudFilesHydrator) refreshProjectedDirectory(
	baseDir string,
	items []cloudPlaceholderInfo,
) error {
	cleanBaseDir := filepath.Clean(baseDir)
	desired := cloudFilesPlaceholderMap(items)

	h.projectionMu.Lock()
	defer h.projectionMu.Unlock()
	if h.projectedDirectories == nil {
		h.projectedDirectories = map[string]map[string]cloudPlaceholderInfo{}
	}
	previous := h.projectedDirectories[cleanBaseDir]
	next := make(map[string]cloudPlaceholderInfo, len(desired))

	for relativePath, item := range desired {
		oldItem, alreadyProjected := previous[relativePath]
		virtualPath := cloudFilesLocalPathToVirtual(
			h.syncRoot,
			filepath.Join(cleanBaseDir, filepath.FromSlash(relativePath)),
		)
		if h.preserveLocalProjection(virtualPath, item.IsDirectory) {
			if alreadyProjected {
				next[relativePath] = oldItem
			}
			continue
		}
		if !alreadyProjected {
			created, err := h.createProjectedPlaceholder(cleanBaseDir, item)
			if err != nil {
				return err
			}
			if created {
				next[relativePath] = item
			}
			continue
		}
		if cloudFilesPlaceholderMatches(oldItem, item) {
			next[relativePath] = item
			continue
		}

		localPath := filepath.Join(cleanBaseDir, filepath.FromSlash(relativePath))
		if _, err := os.Lstat(localPath); os.IsNotExist(err) {
			created, createErr := h.createProjectedPlaceholder(cleanBaseDir, item)
			if createErr != nil {
				return createErr
			}
			if created {
				next[relativePath] = item
			} else {
				next[relativePath] = oldItem
			}
			continue
		} else if err != nil {
			return fmt.Errorf("stat Cloud Files placeholder %q: %w", localPath, err)
		}

		h.watcher.RememberPlaceholders(cleanBaseDir, []cloudPlaceholderInfo{item})
		updated, err := h.provider.UpdatePlaceholder(localPath, item)
		if err != nil {
			return err
		}
		if updated {
			next[relativePath] = item
		} else {
			next[relativePath] = oldItem
		}
	}

	for relativePath, oldItem := range previous {
		if _, stillRemote := desired[relativePath]; stillRemote {
			continue
		}
		virtualPath := cloudFilesLocalPathToVirtual(
			h.syncRoot,
			filepath.Join(cleanBaseDir, filepath.FromSlash(relativePath)),
		)
		if h.preserveLocalProjection(virtualPath, oldItem.IsDirectory) {
			next[relativePath] = oldItem
			continue
		}
		if err := h.removeProjectedPlaceholder(cleanBaseDir, oldItem); err != nil {
			return err
		}
	}

	h.projectedDirectories[cleanBaseDir] = next
	h.watcher.watchPlaceholderDirectories(cleanBaseDir, items)
	return nil
}

func (h *cloudFilesHydrator) createProjectedPlaceholder(
	baseDir string,
	item cloudPlaceholderInfo,
) (bool, error) {
	localPath := filepath.Join(baseDir, filepath.FromSlash(item.RelativePath))
	if _, err := os.Lstat(localPath); err == nil {
		// An untracked local item belongs to Explorer or writeback, not this poll.
		return false, nil
	} else if !os.IsNotExist(err) {
		return false, fmt.Errorf("stat new Cloud Files placeholder %q: %w", localPath, err)
	}
	h.watcher.RememberPlaceholders(baseDir, []cloudPlaceholderInfo{item})
	if err := h.provider.CreatePlaceholders(baseDir, []cloudPlaceholderInfo{item}); err != nil {
		return false, err
	}
	return true, nil
}

func (h *cloudFilesHydrator) removeProjectedPlaceholder(
	baseDir string,
	item cloudPlaceholderInfo,
) error {
	localPath := filepath.Join(baseDir, filepath.FromSlash(item.RelativePath))
	if !isLocalPathWithinRoot(h.syncRoot, localPath) {
		return fmt.Errorf("placeholder path escapes sync root: %q", item.RelativePath)
	}
	info, err := os.Lstat(localPath)
	if os.IsNotExist(err) {
		h.watcher.Forget(localPath)
		return nil
	}
	if err != nil {
		return fmt.Errorf("stat removed Cloud Files placeholder: %w", err)
	}
	removeTree := item.IsDirectory || info.IsDir()
	h.watcher.MarkProviderDelete(localPath, removeTree)
	if removeTree {
		err = os.RemoveAll(localPath)
	} else {
		err = os.Remove(localPath)
	}
	if err != nil {
		h.watcher.ClearProviderDelete(localPath)
		return fmt.Errorf("remove remote Cloud Files placeholder: %w", err)
	}
	h.watcher.Forget(localPath)
	return nil
}

func (h *cloudFilesHydrator) preserveLocalProjection(
	virtualPath string,
	isDir bool,
) bool {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" || h.access.cache.isMarkedDeleted(clean) {
		return true
	}
	if _, local := h.access.cache.localEntry(clean); local {
		return true
	}
	return h.access.writeback != nil && h.access.writeback.hasPendingAtOrBelow(clean, isDir)
}

func cloudFilesPlaceholderMap(
	items []cloudPlaceholderInfo,
) map[string]cloudPlaceholderInfo {
	result := make(map[string]cloudPlaceholderInfo, len(items))
	for _, item := range items {
		if item.RelativePath != "" {
			result[item.RelativePath] = item
		}
	}
	return result
}

func cloudFilesPlaceholderMatches(
	left, right cloudPlaceholderInfo,
) bool {
	return left.FileSize == right.FileSize &&
		left.FileID == right.FileID &&
		left.Fingerprint == right.Fingerprint &&
		left.IsDirectory == right.IsDirectory &&
		left.ModTime.Equal(right.ModTime)
}
