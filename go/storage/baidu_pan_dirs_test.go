// Baidu Pan directory tests exercise mkdir behavior through fake SDK HTTP calls.
package storage

import (
	"io"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	xpanauth "github.com/lfhy/xpan/auth"
	xpanclient "github.com/lfhy/xpan/client"
	xpanhttp "github.com/lfhy/xpan/http"
)

type baiduPanDirRoundTrip func(*http.Request) (*http.Response, error)

func (f baiduPanDirRoundTrip) Do(req *http.Request) (*http.Response, error) {
	return f(req)
}

func TestEnsureBaiduPanDirCreatesPathOnceWhenConcurrent(t *testing.T) {
	resetBaiduPanKnownDirsForTest()
	defer resetBaiduPanKnownDirsForTest()

	var mkdirs int32
	xpanhttp.SetClient(baiduPanDirRoundTrip(func(req *http.Request) (*http.Response, error) {
		body := `{"errno":0,"list":[]}`
		if req.Method == http.MethodPost && strings.Contains(req.URL.RawQuery, "method=create") {
			atomic.AddInt32(&mkdirs, 1)
			body = `{"fs_id":1,"path":"/AI/codex-concurrent","server_filename":"codex-concurrent","isdir":1}`
		}
		return &http.Response{
			StatusCode: http.StatusOK,
			Body:       io.NopCloser(strings.NewReader(body)),
		}, nil
	}))
	defer xpanhttp.SetClient(http.DefaultClient)

	client := xpanclient.New(&xpanauth.AuthEnv{AccessToken: "test-token"})
	var wg sync.WaitGroup
	errs := make(chan error, 4)
	for range 4 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			errs <- ensureBaiduPanDir(client, "/AI/codex-concurrent")
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatalf("ensureBaiduPanDir returned error: %v", err)
		}
	}
	if got := atomic.LoadInt32(&mkdirs); got != 2 {
		t.Fatalf("mkdir calls = %d, want 2 for /AI and child", got)
	}
}
