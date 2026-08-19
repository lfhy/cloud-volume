// Read APIs materialize provider listings into the durable inode view.
package metadata

import (
	"context"
	"errors"
	"fmt"
	"time"

	bolt "go.etcd.io/bbolt"
)

// MaterializeDirectory synchronously lists one directory from the provider and
// commits the resulting dirents/inodes in one transaction.
func (s *Service) MaterializeDirectory(ctx context.Context, dirInode uint64) error {
	directoryPath, err := s.materializeDirectoryPath(dirInode)
	if err != nil {
		return err
	}
	items, err := listProviderChildrenImpl(ctx, s.backendSnapshot(), s.store.namespace.Bucket, dirInode, func(uint64) (string, error) {
		return directoryPath, nil
	})
	if err != nil {
		return err
	}
	return s.store.update(func(tx *bolt.Tx) error {
		parent, err := getInode(tx, dirInode)
		if err != nil {
			return err
		}
		if parent.Kind != KindDirectory {
			return fmt.Errorf("metadata: inode %d is not a directory", dirInode)
		}
		children, err := tx.Bucket([]byte(bucketDirents)).CreateBucketIfNotExists(encodeUint64(dirInode))
		if err != nil {
			return err
		}
		remoteByKey := map[string]Dirent{}
		_ = children.ForEach(func(_, value []byte) error {
			var dirent Dirent
			if err := decodeJSON(value, &dirent); err == nil {
				remoteByKey[dirent.NameKey] = dirent
			}
			return nil
		})
		priorByKey := map[string]Inode{}
		for key, dirent := range remoteByKey {
			if prior, err := getInode(tx, dirent.ChildID); err == nil {
				priorByKey[key] = prior
			}
		}
		suppressedRemoteKeys := pendingRemoteKeysToSuppress(tx, dirInode)
		nextByKey := map[string]Dirent{}
		for _, item := range items {
			name, isDir, err := splitListedChild(directoryPath, item.Key)
			if err != nil {
				continue
			}
			nameKey := MakeNameKey(name)
			if suppressedRemoteKeys[nameKey] {
				continue
			}
			existing := remoteByKey[nameKey]
			inode := existing.ChildID
			if inode == 0 {
				inode, err = allocateInode(tx)
				if err != nil {
					return err
				}
			}
			record := Inode{
				ID: inode, Kind: KindFile, DesiredParentID: dirInode,
				DesiredName: name, RemoteParentID: dirInode, RemoteName: name,
				Size: item.Size, MTime: item.LastModified, RemoteMTime: item.LastModified, ETag: item.ETag,
				RemoteFingerprint: Fingerprint(item), State: StateSynced,
			}
			if isDir {
				record.Kind = KindDirectory
			}
			// Preserve the whole prior record for local pending work. Rebuilding
			// it from provider data would drop ContentGeneration and orphan
			// staged chunk-backed content.
			if prior, ok := priorByKey[nameKey]; ok && (prior.State == StatePending || prior.State == StateConflict) {
				// A pending cross-directory rename has already installed its Desired
				// dirent in the target before that directory is materialized. A
				// same-name remote object there is not confirmation of the source
				// edge; accepting it would make the worker think its move is a no-op.
				if prior.RemoteParentID != dirInode || MakeNameKey(prior.RemoteName) != nameKey {
					continue
				}
				desiredParent, desiredName, state := record.DesiredParentID, record.DesiredName, record.State
				record = prior
				record.Kind = KindFile
				if isDir {
					record.Kind = KindDirectory
				}
				record.RemoteParentID, record.RemoteName = dirInode, name
				if item.LastModified != "" {
					record.RemoteMTime = item.LastModified
				}
				record.ETag = item.ETag
				record.RemoteFingerprint = Fingerprint(item)
				record.DesiredParentID, record.DesiredName, record.State = desiredParent, desiredName, state
			}
			if err := putInode(tx, record); err != nil {
				return err
			}
			nextByKey[nameKey] = Dirent{ChildID: inode, DisplayName: name, NameKey: nameKey}
		}
		for key, dirent := range remoteByKey {
			if _, ok := nextByKey[key]; ok {
				continue
			}
			if prior, ok := priorByKey[key]; ok && (prior.State == StatePending || prior.State == StateConflict) {
				nextByKey[key] = dirent
			}
		}
		if err := children.ForEach(func(key, _ []byte) error { return children.Delete(key) }); err != nil {
			return err
		}
		for _, dirent := range nextByKey {
			if err := putDirent(tx, dirInode, dirent); err != nil {
				return err
			}
		}
		parent.LocalRevision++
		if err := putInode(tx, parent); err != nil {
			return err
		}
		return putListingState(tx, ListingState{Inode: dirInode, Materialized: true, Revision: parent.LocalRevision, VerifiedAtUnixNano: time.Now().UnixNano()})
	})
}

// materializeDirectoryPath retains a renamed directory's confirmed remote
// source until its move journal entry finishes. Its Desired name can already
// differ, but the provider still lists children below the old remote path.
func (s *Service) materializeDirectoryPath(inode uint64) (string, error) {
	desired, err := s.Path(inode)
	if err != nil {
		return "", err
	}
	var record Inode
	err = s.store.view(func(tx boltTxT) error {
		value, err := getInode(tx, inode)
		record = value
		return err
	})
	if err != nil {
		return "", err
	}
	if (record.State != StatePending && record.State != StateConflict) || record.RemoteParentID == 0 || record.RemoteName == "" {
		return desired, nil
	}
	remote, remoteErr := s.remotePathLocked(record.RemoteParentID, record.RemoteName)
	if remoteErr != nil {
		return desired, nil
	}
	return remote, nil
}

// pendingRemoteKeysToSuppress keeps a remote listing from reviving the source
// of a local rename or a tombstoned entry before its journal work confirms.
func pendingRemoteKeysToSuppress(tx boltTx, parent uint64) map[string]bool {
	suppressed := map[string]bool{}
	inodes := tx.Bucket([]byte(bucketInodes))
	if inodes == nil {
		return suppressed
	}
	_ = inodes.ForEach(func(_, value []byte) error {
		var record Inode
		if decodeJSON(value, &record) != nil || record.RemoteParentID != parent || record.RemoteName == "" {
			return nil
		}
		if record.State != StatePending && record.State != StateConflict && record.State != StateTombstone {
			return nil
		}
		remoteKey := MakeNameKey(record.RemoteName)
		if record.State == StateTombstone || record.DesiredParentID != parent || MakeNameKey(record.DesiredName) != remoteKey {
			suppressed[remoteKey] = true
		}
		return nil
	})
	return suppressed
}

// StatPath resolves one desired-tree path, materializing ancestors as needed.
func (s *Service) StatPath(ctx context.Context, path string) (Object, error) {
	inode, err := s.resolvePath(ctx, path)
	if err != nil {
		return Object{}, err
	}
	return s.StatInode(ctx, inode)
}

// StatInode returns one inode's desired object view.
func (s *Service) StatInode(_ context.Context, inode uint64) (Object, error) {
	var object Object
	err := s.store.view(func(tx *bolt.Tx) error {
		record, err := getInode(tx, inode)
		if err != nil {
			return err
		}
		if record.State == StateTombstone {
			return ErrNotFound
		}
		path, err := s.pathLocked(tx, record.ID)
		if err != nil {
			return err
		}
		object = objectFromInode(record, path)
		return nil
	})
	return object, err
}

// ListPage returns one deterministic slice of a materialized directory.
func (s *Service) ListPage(ctx context.Context, dirInode uint64, token string, pageSize int32) (Page, error) {
	if pageSize <= 0 {
		pageSize = 200
	}
	var cursor Cursor
	if token != "" {
		parsed, err := DecodeCursor(token)
		if err != nil {
			return Page{}, err
		}
		if parsed.Inode != dirInode {
			return Page{}, ErrStaleCursor
		}
		cursor = parsed
	}
	if err := s.ensureMaterialized(ctx, dirInode, cursor.Revision); err != nil {
		return Page{}, err
	}
	var page Page
	err := s.store.view(func(tx *bolt.Tx) error {
		parent, err := getInode(tx, dirInode)
		if err != nil {
			return err
		}
		if cursor.Version != 0 && cursor.Revision != parent.LocalRevision {
			return ErrStaleCursor
		}
		children := tx.Bucket([]byte(bucketDirents)).Bucket(encodeUint64(dirInode))
		if children == nil {
			page.Items = []Object{}
			return nil
		}
		start := children.Cursor()
		prefix := []byte(cursor.LastNameKey)
		for key, value := start.Seek(prefix); key != nil; key, value = start.Next() {
			if cursor.LastNameKey != "" && string(key) == cursor.LastNameKey {
				continue
			}
			var dirent Dirent
			if decodeJSON(value, &dirent) != nil {
				continue
			}
			record, err := getInode(tx, dirent.ChildID)
			if err != nil || record.State == StateTombstone {
				continue
			}
			path, err := s.pathLocked(tx, record.ID)
			if err != nil {
				continue
			}
			page.Items = append(page.Items, objectFromInode(record, path))
			if int32(len(page.Items)) == pageSize {
				page.NextToken = EncodeCursor(Cursor{Version: 1, Inode: dirInode, Revision: parent.LocalRevision, LastNameKey: string(key)})
				break
			}
		}
		if page.Items == nil {
			page.Items = []Object{}
		}
		return nil
	})
	return page, err
}

func (s *Service) ensureMaterialized(ctx context.Context, dirInode uint64, revision uint64) error {
	materialized, localOnly := false, false
	_ = s.store.view(func(tx *bolt.Tx) error {
		record, err := getInode(tx, dirInode)
		if err != nil {
			return err
		}
		// A newly created directory has no provider edge yet. Its desired
		// dirents are authoritative until the mkdir worker confirms it, so a
		// nested Finder copy must not try to list a remote path that cannot exist.
		localOnly = record.Kind == KindDirectory && record.ID != rootInode && record.RemoteParentID == 0 && record.RemoteName == ""
		state, err := getListingState(tx, dirInode)
		materialized = err == nil && state.Materialized && (revision == 0 || state.Revision == revision)
		return nil
	})
	if materialized || localOnly {
		return nil
	}
	return s.MaterializeDirectory(ctx, dirInode)
}

func (s *Service) resolvePath(ctx context.Context, path string) (uint64, error) {
	segments := SplitPath(path)
	if len(segments) == 0 {
		return rootInode, nil
	}
	current := rootInode
	for index, segment := range segments {
		// Desired dirents are the local metadata cache and the authoritative
		// source for known paths. Materialize only on a miss so a Finder copy
		// does not dial the provider for every already-known parent segment.
		next, err := s.Resolve(current, segment)
		if errors.Is(err, ErrNotFound) {
			if err := s.ensureMaterialized(ctx, current, 0); err != nil {
				return 0, err
			}
			next, err = s.Resolve(current, segment)
		}
		if err != nil {
			return 0, err
		}
		if index == len(segments)-1 {
			return next, nil
		}
		current = next
	}
	return current, nil
}

// Resolve returns the child inode for one display name.
func (s *Service) Resolve(parent uint64, name string) (uint64, error) {
	key := MakeNameKey(name)
	var child uint64
	err := s.store.view(func(tx *bolt.Tx) error {
		dirent, err := getDirent(tx, parent, key)
		if err != nil {
			return err
		}
		child = dirent.ChildID
		return nil
	})
	return child, err
}

// Path derives the current Desired path for one inode.
func (s *Service) Path(inode uint64) (string, error) {
	var pathValue string
	err := s.store.view(func(tx *bolt.Tx) error {
		value, err := s.pathLocked(tx, inode)
		pathValue = value
		return err
	})
	return pathValue, err
}

func (s *Service) pathLocked(tx boltTx, inode uint64) (string, error) {
	if inode == rootInode {
		return "", nil
	}
	segments := make([]string, 0, 8)
	visited := map[uint64]bool{inode: true}
	current := inode
	for depth := 0; depth < 1024; depth++ {
		record, err := getInode(tx, current)
		if err != nil {
			return "", err
		}
		if record.ID == rootInode {
			reverse(segments)
			return JoinPath(segments), nil
		}
		if visited[record.DesiredParentID] {
			return "", ErrCycle
		}
		visited[record.DesiredParentID] = true
		segments = append(segments, record.DesiredName)
		current = record.DesiredParentID
	}
	return "", ErrCycle
}
