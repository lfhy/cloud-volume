// Bulk task-sync bridge dispatch keeps queue-wide scheduling off the UI isolate.
package main

import (
	"encoding/json"

	bucketmetadata "remote-storage/go/mount/metadata"
)

func triggerAllRemoteTasks(args json.RawMessage) (any, error) {
	var input remoteTaskListArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	manager, err := bucketmetadata.DefaultManager()
	if err != nil {
		return nil, err
	}
	handles, err := warmKnownTaskNamespaces(manager, input)
	if err != nil {
		return nil, err
	}
	defer releaseTaskNamespaceHandles(manager, handles)
	triggered, err := manager.TriggerPendingTasksFor(input.ProfileID, input.Bucket)
	if err != nil {
		return nil, err
	}
	return map[string]any{"triggered": triggered}, nil
}
