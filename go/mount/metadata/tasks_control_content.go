// Cancellation content cleanup keeps chunk-link accounting separate from tree rollback.
package metadata

import "bytes"

func releaseContentRefsForCancel(tx boltTxT, inode uint64, generation *uint64) ([]string, error) {
	refs := tx.Bucket([]byte(bucketContentRefs))
	prefix := encodeUint64(inode)
	cursor := refs.Cursor()
	type storedRef struct {
		key []byte
		ref ContentRef
	}
	var found []storedRef
	for key, value := cursor.Seek(prefix); key != nil && bytes.HasPrefix(key, prefix); key, value = cursor.Next() {
		var ref ContentRef
		if err := decodeJSON(value, &ref); err != nil {
			return nil, err
		}
		if generation == nil || ref.Generation == *generation {
			found = append(found, storedRef{key: append([]byte(nil), key...), ref: ref})
		}
	}
	deltas := map[string]int64{}
	for _, item := range found {
		for _, hash := range item.ref.Chunks {
			deltas[hash]--
		}
	}
	removed, err := applyChunkDeltas(tx, deltas, nil)
	if err != nil {
		return nil, err
	}
	for _, item := range found {
		if err := refs.Delete(item.key); err != nil {
			return nil, err
		}
	}
	return removed, nil
}
