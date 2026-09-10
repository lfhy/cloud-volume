// Resume download tests verify range-based continuation against an S3-compatible endpoint.
package s3

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	storageconfig "remote-storage/go/config"
)

func TestDownloadFileContextResumesFromPartialFile(t *testing.T) {
	t.Parallel()

	const body = "hello world"
	var (
		mu         sync.Mutex
		rangeValue string
	)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/bucket/object.txt" {
			http.NotFound(w, r)
			return
		}
		switch r.Method {
		case http.MethodHead:
			w.Header().Set("Content-Length", fmt.Sprintf("%d", len(body)))
			w.Header().Set("Last-Modified", "Tue, 26 May 2026 22:00:00 GMT")
			w.WriteHeader(http.StatusOK)
		case http.MethodGet:
			mu.Lock()
			rangeValue = r.Header.Get("Range")
			mu.Unlock()
			if rangeValue == "bytes=5-" {
				w.Header().Set("Content-Length", "6")
				w.Header().Set("Content-Range", "bytes 5-10/11")
				w.WriteHeader(http.StatusPartialContent)
				_, _ = w.Write([]byte(body[5:]))
				return
			}
			w.Header().Set("Content-Length", fmt.Sprintf("%d", len(body)))
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(body))
		default:
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	}))
	defer server.Close()

	cfg := storageconfig.RemoteStorageConfig{
		Endpoint:        server.URL,
		Region:          "us-east-1",
		AccessKeyID:     "test",
		SecretAccessKey: "test",
		UsePathStyle:    true,
	}
	localPath := filepath.Join(t.TempDir(), "object.txt")
	if err := os.WriteFile(localPath, []byte("hello"), 0o644); err != nil {
		t.Fatalf("seed partial file: %v", err)
	}

	if err := DownloadFileContext(context.Background(), cfg, "bucket", "object.txt", localPath, ""); err != nil {
		t.Fatalf("DownloadFileContext: %v", err)
	}

	data, err := os.ReadFile(localPath)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if string(data) != body {
		t.Fatalf("unexpected downloaded content %q", string(data))
	}
	mu.Lock()
	defer mu.Unlock()
	if rangeValue != "bytes=5-" {
		t.Fatalf("expected ranged resume request, got %q", rangeValue)
	}
}

func TestTrackedSmallFileUploadsUsePrecomputedPayloadHash(t *testing.T) {
	const body = "tracked upload payload"
	wantHash := sha256.Sum256([]byte(body))

	for _, upload := range []struct {
		name string
		key  string
		run  func(storageconfig.RemoteStorageConfig, string, string) error
	}{
		{
			name: "direct",
			key:  "direct.txt",
			run: func(cfg storageconfig.RemoteStorageConfig, localPath, taskID string) error {
				return UploadFileContext(context.Background(), cfg, "bucket", "direct.txt", localPath, taskID)
			},
		},
		{
			name: "resumable_whole_object",
			key:  "resumable.txt",
			run: func(cfg storageconfig.RemoteStorageConfig, localPath, taskID string) error {
				return UploadFileContextResumable(
					context.Background(), cfg, "bucket", "resumable.txt", localPath, taskID, 0,
				)
			},
		},
	} {
		t.Run(upload.name, func(t *testing.T) {
			type request struct {
				method      string
				path        string
				payload     string
				payloadHash string
				err         error
			}
			requestSeen := make(chan request, 1)
			allowResponse := make(chan struct{})
			responseReleased := false
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				// NewClient probes whether the endpoint is a JWanFS gateway before
				// it creates the S3 client. Only the subsequent PUT is under test.
				if r.Method != http.MethodPut {
					http.NotFound(w, r)
					return
				}
				payload, err := io.ReadAll(r.Body)
				requestSeen <- request{
					method:      r.Method,
					path:        r.URL.Path,
					payload:     string(payload),
					payloadHash: r.Header.Get("X-Amz-Content-Sha256"),
					err:         err,
				}
				<-allowResponse
				w.Header().Set("ETag", `"uploaded"`)
				w.WriteHeader(http.StatusOK)
			}))
			defer server.Close()
			defer func() {
				if !responseReleased {
					close(allowResponse)
				}
			}()

			cfg := storageconfig.RemoteStorageConfig{
				Endpoint:        server.URL,
				Region:          "us-east-1",
				AccessKeyID:     "test",
				SecretAccessKey: "test",
				UsePathStyle:    true,
			}
			localPath := filepath.Join(t.TempDir(), "tracked.txt")
			if err := os.WriteFile(localPath, []byte(body), 0o644); err != nil {
				t.Fatalf("write local source: %v", err)
			}
			taskID := "tracked-seekable-" + upload.name
			t.Cleanup(func() { ForgetTransfer(taskID) })
			done := make(chan error, 1)
			go func() { done <- upload.run(cfg, localPath, taskID) }()

			var gotRequest request
			select {
			case gotRequest = <-requestSeen:
			case <-time.After(5 * time.Second):
				t.Fatal("timed out waiting for upload request")
			}
			if gotRequest.err != nil {
				t.Fatalf("read upload request: %v", gotRequest.err)
			}
			if gotRequest.method != http.MethodPut || gotRequest.path != "/bucket/"+upload.key {
				t.Fatalf("request = %s %s, want PUT /bucket/%s", gotRequest.method, gotRequest.path, upload.key)
			}
			if gotRequest.payload != body {
				t.Fatalf("uploaded body = %q, want %q", gotRequest.payload, body)
			}
			if gotRequest.payloadHash != hex.EncodeToString(wantHash[:]) {
				t.Fatalf("payload hash = %q, want %x", gotRequest.payloadHash, wantHash)
			}

			snapshot, ok := GetTransferSnapshot(taskID)
			if !ok {
				t.Fatal("tracked upload snapshot disappeared before response")
			}
			if snapshot.Status != "running" {
				t.Fatalf("snapshot status before response = %q, want running", snapshot.Status)
			}
			if snapshot.BytesCompleted != int64(len(body)) || snapshot.BytesCompleted > snapshot.TotalBytes {
				t.Fatalf(
					"snapshot progress before response = %d/%d, want %d/%d",
					snapshot.BytesCompleted,
					snapshot.TotalBytes,
					len(body),
					len(body),
				)
			}

			close(allowResponse)
			responseReleased = true
			if err := <-done; err != nil {
				t.Fatalf("upload tracked small file: %v", err)
			}
			snapshot, ok = GetTransferSnapshot(taskID)
			if !ok || snapshot.Status != "done" || snapshot.BytesCompleted != snapshot.TotalBytes {
				t.Fatalf("final snapshot = %#v, want done at total bytes", snapshot)
			}
		})
	}
}
