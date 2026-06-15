//go:build windows && cgo

// Cloud Files sync-state projection keeps Explorer status aligned with writeback queue state.
package mount

import "path/filepath"

type cloudFilesSyncStateProjector struct {
	rootPath string
	provider *cloudFilesProvider
}

func newCloudFilesSyncStateProjector(
	rootPath string,
	provider *cloudFilesProvider,
) *cloudFilesSyncStateProjector {
	return &cloudFilesSyncStateProjector{
		rootPath: rootPath,
		provider: provider,
	}
}

func (p *cloudFilesSyncStateProjector) UpdateSyncState(
	virtualPath string,
	inSync bool,
) error {
	if p == nil || p.provider == nil {
		return nil
	}
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return nil
	}
	localPath := filepath.Join(p.rootPath, filepath.FromSlash(clean))
	return p.provider.SetInSync(localPath, inSync)
}
