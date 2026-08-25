//go:build linux

// Linux OID tests pin persistent metadata identities over path-hash fallback.
package mount

import "testing"

func TestLinuxFuseStableAttrUsesMetadataOID(t *testing.T) {
	attr := linuxFuseStableAttrWithOID("before-rename.txt", false, 42)
	if attr.Ino != 42 {
		t.Fatalf("metadata inode = %d, want 42", attr.Ino)
	}
	afterRename := linuxFuseStableAttrWithOID("after-rename.txt", false, 42)
	if afterRename.Ino != attr.Ino {
		t.Fatalf("rename changed metadata inode: before=%d after=%d", attr.Ino, afterRename.Ino)
	}
}
