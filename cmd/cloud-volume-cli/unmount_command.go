// The unmount command stops the live mount session for the requested bucket.
package main

import (
	"encoding/json"

	bucketmount "remote-storage/go/mount"
)

func runUnmountCommand(args []string) error {
	request, err := parseBucketRequest("unmount", args)
	if err != nil {
		return err
	}

	mountPath, err := bucketmount.ResolveMountPath(request.bucket, bucketmount.MountOptions{
		MountPath: request.mountPath,
	})
	if err != nil {
		return err
	}
	if err := bucketmount.UnmountMountPath(mountPath); err != nil {
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
