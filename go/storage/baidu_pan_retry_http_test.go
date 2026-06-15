// Baidu Pan retry HTTP tests keep transient upstream throttling recoverable.
package storage

import (
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestBaiduPanRetryHTTPClientRetriesThrottle403(t *testing.T) {
	originalDelays := baiduPanThrottleRetryDelays
	baiduPanThrottleRetryDelays = []time.Duration{time.Millisecond}
	defer func() { baiduPanThrottleRetryDelays = originalDelays }()

	attempts := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		attempts++
		if attempts == 1 {
			w.WriteHeader(http.StatusForbidden)
			_, _ = w.Write([]byte("rate limit"))
			return
		}
		_, _ = w.Write([]byte(`{"errno":0}`))
	}))
	defer server.Close()

	req, err := http.NewRequest(http.MethodGet, server.URL+"/rest/2.0/xpan/file", nil)
	if err != nil {
		t.Fatalf("NewRequest returned error: %v", err)
	}
	resp, err := newBaiduPanRetryHTTPClient().Do(req)
	if err != nil {
		t.Fatalf("Do returned error: %v", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("ReadAll returned error: %v", err)
	}
	if attempts != 2 {
		t.Fatalf("attempts = %d, want 2", attempts)
	}
	if resp.StatusCode != http.StatusOK || string(body) != `{"errno":0}` {
		t.Fatalf("unexpected response status=%d body=%q", resp.StatusCode, body)
	}
}

func TestBaiduPanRetryHTTPClientDoesNotRetryAuth403(t *testing.T) {
	originalDelays := baiduPanThrottleRetryDelays
	baiduPanThrottleRetryDelays = []time.Duration{time.Millisecond}
	defer func() { baiduPanThrottleRetryDelays = originalDelays }()

	attempts := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		attempts++
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte("invalid token"))
	}))
	defer server.Close()

	req, err := http.NewRequest(http.MethodGet, server.URL+"/oauth/2.0/token", nil)
	if err != nil {
		t.Fatalf("NewRequest returned error: %v", err)
	}
	resp, err := newBaiduPanRetryHTTPClient().Do(req)
	if err != nil {
		t.Fatalf("Do returned error: %v", err)
	}
	defer resp.Body.Close()
	if attempts != 1 {
		t.Fatalf("attempts = %d, want 1", attempts)
	}
	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("status = %d, want %d", resp.StatusCode, http.StatusForbidden)
	}
}

func TestBaiduPanThrottleErrorMatchesSDKFrequencyText(t *testing.T) {
	t.Parallel()

	if !isBaiduPanThrottleError(errString("hit frequency limit")) {
		t.Fatalf("expected SDK frequency text to be retryable")
	}
	if !isBaiduPanThrottleError(errString("请求过于频繁")) {
		t.Fatalf("expected Chinese frequency text to be retryable")
	}
	if isBaiduPanThrottleError(errString("invalid token")) {
		t.Fatalf("auth errors must not be treated as throttling")
	}
}

type errString string

func (e errString) Error() string {
	return string(e)
}
