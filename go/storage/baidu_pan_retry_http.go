// Baidu Pan HTTP retry client absorbs transient RPM throttling before SDK calls fail.
package storage

import (
	"bytes"
	"fmt"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"
)

const baiduPanThrottleRetryCount = 5

var baiduPanThrottleRetryDelays = []time.Duration{
	3 * time.Second,
	8 * time.Second,
	15 * time.Second,
	30 * time.Second,
	60 * time.Second,
}

type baiduPanRetryHTTPClient struct {
	client *http.Client
}

func newBaiduPanRetryHTTPClient() *baiduPanRetryHTTPClient {
	return &baiduPanRetryHTTPClient{client: &http.Client{}}
}

func (c *baiduPanRetryHTTPClient) Do(req *http.Request) (*http.Response, error) {
	var lastResp *http.Response
	for attempt := 0; attempt <= baiduPanThrottleRetryCount; attempt++ {
		nextReq, err := cloneBaiduPanRetryRequest(req)
		if err != nil {
			return nil, err
		}
		resp, err := c.client.Do(nextReq)
		if err != nil {
			return resp, err
		}
		if resp.StatusCode != http.StatusForbidden {
			return resp, nil
		}
		body, readErr := io.ReadAll(resp.Body)
		_ = resp.Body.Close()
		if readErr != nil {
			return nil, readErr
		}
		resp.Body = io.NopCloser(bytes.NewReader(body))
		if !isBaiduPanThrottleResponse(resp, body) || attempt == baiduPanThrottleRetryCount {
			return resp, nil
		}
		lastResp = resp
		delay := baiduPanThrottleRetryDelay(resp, attempt)
		log.Printf(
			"[storage/baidu-pan] throttled url=%q attempt=%d sleep=%s",
			redactBaiduPanAccessToken(req.URL.String()),
			attempt+1,
			delay,
		)
		timer := time.NewTimer(delay)
		select {
		case <-req.Context().Done():
			timer.Stop()
			return nil, req.Context().Err()
		case <-timer.C:
		}
	}
	if lastResp != nil {
		return lastResp, nil
	}
	return nil, fmt.Errorf("baidu pan throttled request did not return a response")
}

func cloneBaiduPanRetryRequest(req *http.Request) (*http.Request, error) {
	if req.Body == nil {
		return req.Clone(req.Context()), nil
	}
	if req.GetBody != nil {
		cloned := req.Clone(req.Context())
		body, err := req.GetBody()
		if err != nil {
			return nil, err
		}
		cloned.Body = body
		return cloned, nil
	}
	body, err := io.ReadAll(req.Body)
	if err != nil {
		return nil, err
	}
	_ = req.Body.Close()
	req.Body = io.NopCloser(bytes.NewReader(body))
	req.GetBody = func() (io.ReadCloser, error) {
		return io.NopCloser(bytes.NewReader(body)), nil
	}
	cloned := req.Clone(req.Context())
	cloned.Body = io.NopCloser(bytes.NewReader(body))
	return cloned, nil
}

func isBaiduPanThrottleResponse(resp *http.Response, body []byte) bool {
	if resp.Request == nil || resp.Request.URL == nil {
		return false
	}
	if strings.Contains(resp.Request.URL.Path, "/oauth/") {
		return false
	}
	if resp.Request.URL.Host == "pan.baidu.com" ||
		strings.Contains(resp.Request.URL.Host, "baidupcs") {
		return true
	}
	return isBaiduPanThrottleText(string(body))
}

func isBaiduPanThrottleError(err error) bool {
	if err == nil {
		return false
	}
	return isBaiduPanThrottleText(err.Error())
}

func isBaiduPanThrottleText(raw string) bool {
	text := strings.ToLower(raw)
	if strings.Contains(text, "rate") ||
		strings.Contains(text, "limit") ||
		strings.Contains(text, "too many") ||
		strings.Contains(text, "quota") ||
		strings.Contains(text, "frequency") ||
		strings.Contains(text, "频") ||
		strings.Contains(text, "限流") ||
		strings.Contains(text, "过于频繁") {
		return true
	}
	return len(strings.TrimSpace(raw)) == 0
}

func baiduPanThrottleRetryDelay(resp *http.Response, attempt int) time.Duration {
	if resp != nil {
		if retryAfter := strings.TrimSpace(resp.Header.Get("Retry-After")); retryAfter != "" {
			if seconds, err := strconv.Atoi(retryAfter); err == nil && seconds > 0 {
				return time.Duration(seconds) * time.Second
			}
		}
	}
	if attempt < len(baiduPanThrottleRetryDelays) {
		return baiduPanThrottleRetryDelays[attempt]
	}
	return baiduPanThrottleRetryDelays[len(baiduPanThrottleRetryDelays)-1]
}

func redactBaiduPanAccessToken(rawURL string) string {
	if rawURL == "" {
		return rawURL
	}
	parts := strings.Split(rawURL, "access_token=")
	if len(parts) < 2 {
		return rawURL
	}
	tail := parts[1]
	if index := strings.IndexByte(tail, '&'); index >= 0 {
		return parts[0] + "access_token=<redacted>" + tail[index:]
	}
	return parts[0] + "access_token=<redacted>"
}
