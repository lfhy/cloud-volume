// Package mount exposes a small path-based surface for the standalone CLI.
package mount

import "strings"

// ResolveMountPath turns CLI inputs into the actual platform mountpoint path.
func ResolveMountPath(bucket string, options MountOptions) (string, error) {
	return resolveMountPath(normalizeBucketName(bucket), options)
}

// ProbeMountPath reports whether a platform mount currently exists at the path.
func ProbeMountPath(bucket, mountPath string) (BucketMountStatus, error) {
	status := BucketMountStatus{
		Bucket:    normalizeBucketName(bucket),
		MountPath: normalizeMountPath(mountPath),
	}
	mounted, err := probeMountPath(status.MountPath)
	if err != nil {
		return status, err
	}
	status.Mounted = mounted
	return status, nil
}

// UnmountMountPath unmounts a platform mount directly by its resolved path.
func UnmountMountPath(mountPath string) error {
	return unmountMountPath(strings.TrimSpace(mountPath))
}
