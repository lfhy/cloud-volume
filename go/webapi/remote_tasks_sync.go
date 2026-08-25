// Web bulk task sync applies the authenticated profile scope before scheduling work.
package webapi

import (
	"errors"
	"net/http"
	"strings"

	storageconfig "remote-storage/go/config"
	bucketmetadata "remote-storage/go/mount/metadata"
)

func triggerAllWebRemoteTasks(input invokeEnvelope) (any, error) {
	config, err := loadCurrentConfig()
	if err != nil {
		return nil, err
	}
	profileID, err := webTaskSyncProfileID(config)
	if err != nil {
		return nil, err
	}
	config.ProfileID = profileID
	manager, err := bucketmetadata.DefaultManager()
	if err != nil {
		return nil, err
	}
	handles, err := warmWebTaskNamespaces(manager, config, input.Bucket)
	if err != nil {
		return nil, err
	}
	defer releaseWebTaskHandles(manager, handles)
	triggered, err := manager.TriggerPendingTasksFor(profileID, input.Bucket)
	if err != nil {
		return nil, err
	}
	return map[string]any{"triggered": triggered}, nil
}

// webTaskSyncProfileID rejects an empty active profile rather than letting the
// manager's intentionally empty scope mean every retained namespace.
func webTaskSyncProfileID(config storageconfig.RemoteStorageConfig) (string, error) {
	profileID := strings.TrimSpace(config.ProfileID)
	if profileID == "" {
		return "", bucketmetadata.ErrNotFound
	}
	return profileID, nil
}

// webTaskSyncErrorStatus keeps API clients from mistaking a rejected bulk
// action for a successful zero-task response.
func webTaskSyncErrorStatus(err error) int {
	if errors.Is(err, bucketmetadata.ErrNotFound) {
		return http.StatusNotFound
	}
	return http.StatusInternalServerError
}
