// Object ordering keeps mounted directory pages stable across WebDAV and Cloud Files views.
package mount

import (
	"sort"
	"strings"

	s3ops "remote-storage/go/s3"
)

func sortObjectInfos(items []s3ops.ObjectInfo) {
	sort.Slice(items, func(i, j int) bool {
		if items[i].IsDir != items[j].IsDir {
			return items[i].IsDir
		}
		return strings.ToLower(items[i].Key) < strings.ToLower(items[j].Key)
	})
}
