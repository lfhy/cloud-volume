package main

import (
	"encoding/json"
	"log"

	storageconfig "remote-storage/go/config"
	bucketmount "remote-storage/go/mount"
)

type mountBucketArgs struct {
	Config  storageconfig.RemoteStorageConfig `json:"config"`
	Bucket  string                            `json:"bucket"`
	Options bucketmount.MountOptions          `json:"options"`
}

type bucketMountArgs struct {
	Bucket           string `json:"bucket"`
	RemoveLocalCache bool   `json:"removeLocalCache"`
}

// Mount bridge methods keep the Flutter layer thin while the Go session owns lifecycle state.
func mountBucket(args json.RawMessage) (any, error) {
	var input mountBucketArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	log.Printf(
		"[bridge/mount] mount bucket=%q path=%q read_only=%t drive_letter=%q",
		input.Bucket,
		input.Options.MountPath,
		input.Options.ReadOnly,
		input.Options.DriveLetter,
	)
	return bucketmount.MountBucketWithOptions(input.Config, input.Bucket, input.Options)
}

func unmountBucket(args json.RawMessage) (any, error) {
	var input bucketMountArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	log.Printf("[bridge/mount] unmount bucket=%q remove_local_cache=%t", input.Bucket, input.RemoveLocalCache)
	return bucketmount.UnmountBucketWithOptions(input.Bucket, bucketmount.UnmountOptions{
		RemoveLocalCache: input.RemoveLocalCache,
	})
}

func getBucketMountStatus(args json.RawMessage) (any, error) {
	var input bucketMountArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return bucketmount.GetBucketMountStatus(input.Bucket)
}

func openBucketMount(args json.RawMessage) (any, error) {
	var input bucketMountArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	log.Printf("[bridge/mount] open bucket=%q", input.Bucket)
	return bucketmount.OpenBucketMount(input.Bucket)
}

func cleanupMounts() (any, error) {
	log.Printf("[bridge/mount] cleanup")
	if err := bucketmount.CleanupMounts(); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func getActiveMountCount() (any, error) {
	return map[string]any{"count": bucketmount.ActiveMountCount()}, nil
}

func listAvailableDriveLetters() (any, error) {
	return bucketmount.AvailableWindowsDriveLetters()
}

func cleanupStaleWindowsProcesses() (any, error) {
	log.Printf("[bridge/mount] cleanup stale windows processes")
	count, err := bucketmount.CleanupStaleWindowsProcesses()
	if err != nil {
		return nil, err
	}
	return map[string]any{"ok": true, "count": count}, nil
}

// sweepOrphanMounts removes leftover managed WebDAV mounts from a previous
// crashed run. The sweep runs in the background because each stubborn volume
// can take tens of seconds to unmount; the bridge call returns immediately so
// app startup and other bridge traffic are never serialized behind it.
func sweepOrphanMounts() (any, error) {
	log.Printf("[bridge/mount] sweep orphan mounts")
	go func() {
		count, err := bucketmount.SweepOrphanMounts()
		if err != nil {
			log.Printf("[bridge/mount] sweep orphan mounts finished count=%d err=%v", count, err)
			return
		}
		log.Printf("[bridge/mount] sweep orphan mounts finished count=%d", count)
	}()
	return map[string]any{"ok": true, "started": true}, nil
}
