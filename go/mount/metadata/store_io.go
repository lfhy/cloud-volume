// Store transaction wrappers isolate bbolt details from metadata logic files.
package metadata

import (
	"context"
	"strings"
	"time"

	bolt "go.etcd.io/bbolt"

	storageops "remote-storage/go/storage"
)

type boltTxT = *bolt.Tx

func (s *Store) update(fn func(*bolt.Tx) error) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.db.Update(fn)
}

func (s *Store) view(fn func(*bolt.Tx) error) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.db.View(fn)
}

type boltTx interface {
	Bucket([]byte) *bolt.Bucket
}

func putInodeBoltTx(tx boltTx, record Inode) error {
	data, err := encodeJSON(record)
	if err != nil {
		return err
	}
	return tx.Bucket([]byte(bucketInodes)).Put(encodeUint64(record.ID), data)
}

func listProviderChildrenImpl(
	ctx context.Context,
	backend Backend,
	bucket string,
	dirInode uint64,
	pathFor func(uint64) (string, error),
) ([]storageops.ObjectInfo, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if pathFor == nil {
		pathFor = func(uint64) (string, error) { return "", nil }
	}
	virtualPath, err := pathFor(dirInode)
	if err != nil {
		return nil, err
	}
	remotePrefix := ""
	if strings.TrimSpace(virtualPath) != "" {
		remotePrefix = strings.Trim(virtualPath, "/") + "/"
	}
	items := make([]storageops.ObjectInfo, 0, 128)
	token := ""
	for {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		pageCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
		page, err := backend.ListObjectsPage(pageCtx, bucket, remotePrefix, token, 1000)
		cancel()
		if err != nil {
			return nil, err
		}
		items = append(items, page.Items...)
		if strings.TrimSpace(page.NextToken) == "" || page.NextToken == token {
			return items, nil
		}
		token = page.NextToken
	}
}
