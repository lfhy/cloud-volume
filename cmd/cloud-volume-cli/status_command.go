// The status command reports whether the requested bucket currently has a live mount.
package main

import (
	"encoding/json"

	bucketmount "remote-storage/go/mount"
)

func runStatusCommand(args []string) error {
	request, err := parseBucketRequest("status", args)
	if err != nil {
		return err
	}

	mountPath, err := bucketmount.ResolveMountPath(request.bucket, bucketmount.MountOptions{
		MountPath: request.mountPath,
	})
	if err != nil {
		return err
	}
	status, err := bucketmount.ProbeMountPath(request.bucket, mountPath)
	if err != nil {
		return err
	}

	encoder := json.NewEncoder(stdoutWriter())
	encoder.SetIndent("", "  ")
	return encoder.Encode(status)
}
