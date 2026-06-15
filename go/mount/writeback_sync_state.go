// Writeback sync-state helpers project delayed uploads back into shell-visible status.
package mount

import "log"

func (a *bucketAccess) projectSyncState(virtualPath string, inSync bool) {
	if a == nil || a.syncState == nil {
		return
	}
	if err := a.syncState.UpdateSyncState(virtualPath, inSync); err != nil {
		log.Printf(
			"[mount/sync-state] bucket=%q path=%q in_sync=%t error=%v",
			a.bucket,
			cleanVirtualPath(virtualPath),
			inSync,
			err,
		)
	}
}
