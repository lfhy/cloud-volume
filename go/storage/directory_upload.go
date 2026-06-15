// Directory upload walks local folders in the backend so Flutter stays responsive.
package storage

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path"
	"path/filepath"
	"strings"
	"sync"
	"time"

	s3ops "remote-storage/go/s3"
)

const directoryUploadConcurrency = 4
const directoryChildStatusDetail = "directory_child"

// UploadDirectory recursively creates remote directories and uploads files.
func UploadDirectory(
	ctx context.Context,
	backend Backend,
	bucket,
	prefix,
	localPath,
	taskID string,
) (err error) {
	cleanPrefix := strings.Trim(strings.TrimSpace(prefix), "/")
	if cleanPrefix != "" {
		cleanPrefix += "/"
	}
	if ctx == nil {
		ctx = context.Background()
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	rootName := filepath.Base(filepath.Clean(localPath))
	rootKey := cleanRemoteJoin(cleanPrefix, rootName)
	if taskID != "" {
		s3ops.StartQueuedTransfer(taskID, "upload", bucket, rootKey, localPath, 0, cancel)
		s3ops.SetTransferStatusDetail(taskID, "scanning")
		defer func() { s3ops.FinishQueuedTransfer(taskID, err) }()
	}
	rootInfo, err := os.Stat(localPath)
	if err != nil {
		return fmt.Errorf("stat local directory: %w", err)
	}
	if !rootInfo.IsDir() {
		return fmt.Errorf("local path is not a directory: %s", localPath)
	}
	plan, err := planDirectoryUpload(ctx, localPath, cleanPrefix, taskID, bucket)
	if err != nil {
		return err
	}
	for _, remoteKey := range plan.directories {
		if err := ctx.Err(); err != nil {
			return err
		}
		if taskID != "" {
			s3ops.SetTransferTarget(taskID, remoteKey+"/")
		}
		if err := createDirectoryPath(ctx, backend, bucket, remoteKey); err != nil {
			return err
		}
	}
	if taskID != "" {
		s3ops.SetTransferStatusDetail(taskID, "uploading")
	}
	return uploadDirectoryFiles(ctx, backend, bucket, plan.files, taskID)
}

func planDirectoryUpload(
	ctx context.Context,
	localPath,
	cleanPrefix,
	taskID,
	bucket string,
) (directoryUploadPlan, error) {
	plan := directoryUploadPlan{}
	err := filepath.WalkDir(localPath, func(currentPath string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		remoteKey, err := directoryUploadRemoteKey(localPath, currentPath, cleanPrefix)
		if err != nil {
			return err
		}
		if entry.IsDir() {
			plan.directories = append(plan.directories, remoteKey)
			return nil
		}
		if entry.Type()&os.ModeType != 0 {
			return nil
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		if taskID != "" {
			s3ops.AddTransferTotal(taskID, info.Size())
			s3ops.AddTransferItems(taskID, 1)
			s3ops.SetTransferTarget(taskID, remoteKey)
		}
		childTaskID := directoryUploadChildTaskID(taskID, remoteKey)
		if childTaskID != "" {
			s3ops.QueueTransfer(childTaskID, "upload", bucket, remoteKey, currentPath, info.Size())
			s3ops.SetTransferStatusDetail(childTaskID, directoryChildStatusDetail)
		}
		plan.files = append(plan.files, directoryUploadFile{
			localPath: currentPath,
			remoteKey: remoteKey,
			size:      info.Size(),
			childID:   childTaskID,
		})
		return nil
	})
	return plan, err
}

func uploadDirectoryFile(
	ctx context.Context,
	backend Backend,
	bucket,
	key,
	localPath string,
	size int64,
	taskID string,
) (int64, error) {
	file, err := os.Open(localPath)
	if err != nil {
		return 0, fmt.Errorf("open local file: %w", err)
	}
	defer file.Close()
	reader := io.Reader(file)
	var bytesRead int64
	if taskID != "" {
		reader = &directoryProgressReader{
			ctx:          ctx,
			reader:       file,
			parentTaskID: taskID,
			childTaskID:  directoryUploadChildTaskID(taskID, key),
			key:          key,
			bytesRead:    &bytesRead,
			bytesReadMu:  &sync.Mutex{},
		}
	}
	err = backend.UploadReader(ctx, bucket, key, reader, size, "", path.Base(localPath))
	return bytesRead, err
}

func uploadDirectoryFiles(
	ctx context.Context,
	backend Backend,
	bucket string,
	files []directoryUploadFile,
	taskID string,
) error {
	if len(files) == 0 {
		return nil
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	jobs := make(chan directoryUploadFile)
	var wg sync.WaitGroup
	var mu sync.Mutex
	failures := directoryUploadFailures{}
	workerCount := directoryUploadWorkerCount(backend, len(files))
	if len(files) < workerCount {
		workerCount = len(files)
	}
	for range workerCount {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for file := range jobs {
				if err := ctx.Err(); err != nil {
					recordDirectoryUploadError(&mu, &failures, err, cancel)
					return
				}
				if taskID != "" {
					s3ops.SetTransferTarget(taskID, file.remoteKey)
					s3ops.SetTransferCurrentFile(taskID, file.remoteKey, file.size)
				}
				if file.childID != "" {
					s3ops.StartQueuedTransfer(file.childID, "upload", bucket, file.remoteKey, file.localPath, file.size, nil)
					s3ops.SetTransferStatusDetail(file.childID, directoryChildStatusDetail)
				}
				if err := uploadDirectoryFileWithRetry(ctx, backend, bucket, file, taskID); err != nil {
					if file.childID != "" {
						s3ops.FinishQueuedTransfer(file.childID, err)
					}
					log.Printf(
						"[storage/directory-upload] upload-file-error bucket=%q key=%q local_path=%q err=%s",
						bucket,
						file.remoteKey,
						file.localPath,
						describeDirectoryUploadError(err),
					)
					recordDirectoryUploadError(
						&mu,
						&failures,
						fmt.Errorf("upload %s to %s: %w", file.localPath, file.remoteKey, err),
						cancel,
					)
					if isDirectoryUploadStopError(err) {
						return
					}
					continue
				}
				if file.childID != "" {
					s3ops.FinishQueuedTransfer(file.childID, nil)
				}
				if taskID != "" {
					s3ops.AdvanceTransferItems(taskID, 1)
				}
			}
		}()
	}
sendFiles:
	for _, file := range files {
		select {
		case <-ctx.Done():
			break sendFiles
		case jobs <- file:
		}
	}
	close(jobs)
	wg.Wait()
	if err := failures.Err(); err != nil {
		finishUnfinishedDirectoryChildren(files, err)
		return err
	}
	return nil
}

func uploadDirectoryFileWithRetry(
	ctx context.Context,
	backend Backend,
	bucket string,
	file directoryUploadFile,
	taskID string,
) error {
	for attempt := 0; ; attempt++ {
		if attempt > 0 && taskID != "" {
			s3ops.SetTransferCurrentFile(taskID, file.remoteKey, file.size)
		}
		bytesRead, err := uploadDirectoryFile(
			ctx,
			backend,
			bucket,
			file.remoteKey,
			file.localPath,
			file.size,
			taskID,
		)
		if err == nil || isDirectoryUploadStopError(err) {
			return err
		}
		rollbackDirectoryUploadBytes(taskID, file.childID, bytesRead)
		delay, retry := directoryUploadRetryDelay(backend, err, attempt)
		if !retry {
			return err
		}
		log.Printf(
			"[storage/directory-upload] retry-file bucket=%q key=%q local_path=%q attempt=%d sleep=%s err=%s",
			bucket,
			file.remoteKey,
			file.localPath,
			attempt+1,
			delay,
			describeDirectoryUploadError(err),
		)
		if err := sleepDirectoryUploadRetry(ctx, delay); err != nil {
			return err
		}
	}
}

func describeDirectoryUploadError(err error) string {
	if err == nil {
		return "<nil>"
	}
	text := strings.TrimSpace(err.Error())
	if text != "" {
		return text
	}
	return fmt.Sprintf("%T %#v", err, err)
}

func rollbackDirectoryUploadBytes(taskID, childTaskID string, bytesRead int64) {
	if taskID == "" || bytesRead <= 0 {
		return
	}
	s3ops.AdvanceTransfer(taskID, -bytesRead)
	if childTaskID != "" {
		s3ops.AdvanceTransfer(childTaskID, -bytesRead)
	}
}

func recordDirectoryUploadError(
	mu *sync.Mutex,
	failures *directoryUploadFailures,
	err error,
	cancel context.CancelFunc,
) {
	mu.Lock()
	defer mu.Unlock()
	failures.Add(err)
	if isDirectoryUploadStopError(err) {
		cancel()
	}
}

func finishUnfinishedDirectoryChildren(files []directoryUploadFile, err error) {
	for _, file := range files {
		if file.childID == "" {
			continue
		}
		snapshot, ok := s3ops.GetTransferSnapshot(file.childID)
		if !ok || (snapshot.Status != "pending" && snapshot.Status != "running") {
			continue
		}
		s3ops.FinishQueuedTransfer(file.childID, err)
	}
}

func directoryUploadWorkerCount(backend Backend, fileCount int) int {
	workerCount := directoryUploadConcurrency
	if tuned, ok := backend.(interface{ DirectoryUploadConcurrency() int }); ok {
		if value := tuned.DirectoryUploadConcurrency(); value > 0 {
			workerCount = value
		}
	}
	if fileCount > 0 && fileCount < workerCount {
		return fileCount
	}
	return workerCount
}

func directoryUploadRetryDelay(backend Backend, err error, attempt int) (time.Duration, bool) {
	if retryable, ok := backend.(interface {
		DirectoryUploadRetryDelay(error, int) (time.Duration, bool)
	}); ok {
		return retryable.DirectoryUploadRetryDelay(err, attempt)
	}
	return 0, false
}

func sleepDirectoryUploadRetry(ctx context.Context, delay time.Duration) error {
	if delay <= 0 {
		return nil
	}
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

func isDirectoryUploadStopError(err error) bool {
	return errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded)
}

type directoryUploadFailures struct {
	errs []error
}

func (f *directoryUploadFailures) Add(err error) {
	if err == nil {
		return
	}
	f.errs = append(f.errs, err)
}

func (f *directoryUploadFailures) Err() error {
	if len(f.errs) == 0 {
		return nil
	}
	return f
}

func (f *directoryUploadFailures) Error() string {
	if len(f.errs) == 1 {
		return f.errs[0].Error()
	}
	return fmt.Sprintf("%d files failed; first error: %v", len(f.errs), f.errs[0])
}

func directoryUploadRemoteKey(rootPath, currentPath, cleanPrefix string) (string, error) {
	parent := filepath.Dir(filepath.Clean(rootPath))
	relativePath, err := filepath.Rel(parent, currentPath)
	if err != nil {
		return "", err
	}
	parts := strings.Split(filepath.ToSlash(relativePath), "/")
	cleaned := make([]string, 0, len(parts))
	for _, part := range parts {
		if part == "" || part == "." {
			continue
		}
		cleaned = append(cleaned, part)
	}
	return cleanRemoteJoin(cleanPrefix, path.Join(cleaned...)), nil
}

func createDirectoryPath(ctx context.Context, backend Backend, bucket, remoteKey string) error {
	cleanKey := strings.Trim(strings.TrimSpace(remoteKey), "/")
	if cleanKey == "" {
		return nil
	}
	parent, name := path.Split(cleanKey)
	return backend.CreateDirectory(ctx, bucket, parent, name)
}

func cleanRemoteJoin(prefix, key string) string {
	cleanPrefix := strings.Trim(strings.TrimSpace(prefix), "/")
	cleanKey := strings.Trim(strings.TrimSpace(key), "/")
	if cleanPrefix == "" {
		return cleanKey
	}
	if cleanKey == "" {
		return cleanPrefix
	}
	return cleanPrefix + "/" + cleanKey
}

type directoryProgressReader struct {
	ctx          context.Context
	reader       io.Reader
	parentTaskID string
	childTaskID  string
	key          string
	bytesRead    *int64
	bytesReadMu  *sync.Mutex
}

type directoryUploadPlan struct {
	directories []string
	files       []directoryUploadFile
}

type directoryUploadFile struct {
	localPath string
	remoteKey string
	size      int64
	childID   string
}

func (r *directoryProgressReader) Read(p []byte) (int, error) {
	if err := r.ctx.Err(); err != nil {
		return 0, err
	}
	n, err := r.reader.Read(p)
	if n > 0 {
		if r.bytesRead != nil && r.bytesReadMu != nil {
			r.bytesReadMu.Lock()
			*r.bytesRead += int64(n)
			r.bytesReadMu.Unlock()
		}
		s3ops.AdvanceTransferCurrentFile(r.parentTaskID, r.key, int64(n))
		if r.childTaskID != "" {
			s3ops.AdvanceTransfer(r.childTaskID, int64(n))
		}
	}
	return n, err
}

func directoryUploadChildTaskID(parentTaskID, remoteKey string) string {
	if strings.TrimSpace(parentTaskID) == "" {
		return ""
	}
	return parentTaskID + ":file:" + remoteKey
}
