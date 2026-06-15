//go:build windows

// Windows open-path tests pin the shell-success threshold away from explorer exit codes.
package mount

import "testing"

func TestShellExecuteSucceeded(t *testing.T) {
	t.Parallel()

	if shellExecuteSucceeded(32) {
		t.Fatal("expected ShellExecute result 32 to be treated as failure")
	}
	if !shellExecuteSucceeded(33) {
		t.Fatal("expected ShellExecute result 33 to be treated as success")
	}
}
