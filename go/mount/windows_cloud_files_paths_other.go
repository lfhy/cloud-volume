//go:build !windows

// Non-Windows builds need stub Cloud Files path helpers so shared code compiles.
package mount

import "fmt"

func windowsCloudFilesRootPath() (string, error) {
	return "", fmt.Errorf("windows cloud files path is unavailable on this platform")
}
