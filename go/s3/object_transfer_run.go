// Object transfer execution keeps copy/move progress hooks in one place.
package s3

import (
	"context"
	"strings"

	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

type objectTransferTask struct {
	id string
}

func beginObjectTransferTask(
	parent context.Context,
	taskID,
	kind,
	profileID,
	bucket,
	sourceKey,
	targetKey string,
	totalBytes int64,
) (context.Context, objectTransferTask) {
	if parent == nil {
		parent = Ctx()
	}
	if taskID == "" {
		return parent, objectTransferTask{}
	}
	ctx, cancel := context.WithCancel(parent)
	startTransfer(taskID, kind, bucket, sourceKey, "", totalBytes, cancel)
	SetTransferProfile(taskID, profileID)
	setTransferTarget(taskID, targetKey)
	return ctx, objectTransferTask{id: taskID}
}

func (t objectTransferTask) finish(err error) {
	if t.id == "" {
		return
	}
	finishTransfer(t.id, err)
}

func (t objectTransferTask) advance(entry types.Object) {
	if t.id == "" || entry.Size == nil || *entry.Size <= 0 {
		return
	}
	advanceTransfer(t.id, *entry.Size)
}

func executeObjectCopyPlan(
	ctx context.Context,
	client *s3.Client,
	bucket string,
	plan objectTransferPlan,
	task objectTransferTask,
	isDirectory bool,
) error {
	for _, entry := range plan.entries {
		if entry.Key == nil {
			continue
		}
		nextKey := plan.targetPrefix
		if isDirectory {
			nextKey += strings.TrimPrefix(*entry.Key, plan.sourcePrefix)
		}
		if isDirectory && isDirectoryPlaceholderKey(*entry.Key) {
			if err := putDirectoryPlaceholderResilient(ctx, client, bucket, nextKey); err != nil {
				return err
			}
			advanceTransferTaskProgress(task, entry)
			continue
		}
		if err := copyObjectResilient(ctx, client, bucket, *entry.Key, nextKey); err != nil {
			return err
		}
		advanceTransferTaskProgress(task, entry)
	}
	return nil
}
