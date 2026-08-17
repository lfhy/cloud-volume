//go:build windows && cgo

// WinFsp metadata helpers retain persistent OIDs beside directory projections.
package mount

import (
	"context"

	s3ops "remote-storage/go/s3"
)

type winFspDirectoryEntry struct {
	info s3ops.ObjectInfo
	oid  uint64
}

func winFspDirectoryEntries(
	ctx context.Context,
	access *bucketAccess,
	virtualPath string,
	items []s3ops.ObjectInfo,
) []winFspDirectoryEntry {
	oids := access.metadataOIDMap(ctx, virtualPath)
	entries := make([]winFspDirectoryEntry, 0, len(items))
	for _, item := range items {
		entries = append(entries, winFspDirectoryEntry{
			info: item,
			oid:  oids[cleanVirtualPath(item.Key)],
		})
	}
	return entries
}

func winFspVisibleOID(ctx context.Context, access *bucketAccess, virtualPath string) uint64 {
	if oid, ok := access.metadataOIDForVisiblePath(ctx, virtualPath); ok {
		return oid
	}
	return 0
}
