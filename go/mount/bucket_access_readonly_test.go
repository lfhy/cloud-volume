// Read-only mount tests pin write-path rejection across shared bucket access helpers.
package mount

import (
	"context"
	"strings"
	"testing"
)

func TestReadOnlyBucketAccessRejectsMutations(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	access.readOnly = true

	cases := []struct {
		name string
		run  func() error
	}{
		{
			name: "create directory",
			run: func() error {
				return access.createDirectory(context.Background(), "docs")
			},
		},
		{
			name: "delete path",
			run: func() error {
				return access.deletePath(context.Background(), "docs/readme.txt", false)
			},
		},
		{
			name: "rename path",
			run: func() error {
				return access.renamePath(context.Background(), "docs/a.txt", "docs/b.txt", false)
			},
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			err := tc.run()
			if err == nil || !strings.Contains(err.Error(), "read-only") {
				t.Fatalf("expected read-only error, got %v", err)
			}
		})
	}
}
