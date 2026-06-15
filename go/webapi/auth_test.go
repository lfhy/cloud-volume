// Web auth tests keep cookie-gated browser access aligned with WebDAV credentials.
package webapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	storageconfig "remote-storage/go/config"
)

func TestAuthLoginAndCookieProtectedInvoke(t *testing.T) {
	t.Setenv("HOME", t.TempDir())

	config := storageconfig.DefaultConfig()
	config.Endpoint = "https://example.invalid"
	config.AccessKeyID = "ak-test"
	config.SecretAccessKey = "sk-test"
	config.WebDAVUsername = "web-user"
	config.WebDAVPassword = "web-pass"

	if err := storageconfig.SaveProfile("default", config); err != nil {
		t.Fatalf("save profile: %v", err)
	}

	server := NewServer(Options{})
	handler := server.Handler()

	sessionRequest := httptest.NewRequest(http.MethodGet, "/api/auth/session", nil)
	sessionRecorder := httptest.NewRecorder()
	handler.ServeHTTP(sessionRecorder, sessionRequest)
	if sessionRecorder.Code != http.StatusUnauthorized {
		t.Fatalf("expected unauthenticated session status 401, got %d", sessionRecorder.Code)
	}

	mountRequest := httptest.NewRequest(
		http.MethodPost,
		"/api/invoke/mount_bucket",
		strings.NewReader(`{"bucket":"demo"}`),
	)
	mountRequest.Header.Set("Content-Type", "application/json")
	mountRecorder := httptest.NewRecorder()
	handler.ServeHTTP(mountRecorder, mountRequest)
	if mountRecorder.Code != http.StatusUnauthorized {
		t.Fatalf("expected protected invoke to return 401, got %d", mountRecorder.Code)
	}

	loginRequest := httptest.NewRequest(
		http.MethodPost,
		"/api/auth/login",
		strings.NewReader(`{"username":"web-user","password":"web-pass"}`),
	)
	loginRequest.Header.Set("Content-Type", "application/json")
	loginRecorder := httptest.NewRecorder()
	handler.ServeHTTP(loginRecorder, loginRequest)
	if loginRecorder.Code != http.StatusOK {
		t.Fatalf("expected login status 200, got %d body=%s", loginRecorder.Code, loginRecorder.Body.String())
	}

	response := loginRecorder.Result()
	cookies := response.Cookies()
	if len(cookies) == 0 {
		t.Fatal("expected login to set a session cookie")
	}

	authedSessionRequest := httptest.NewRequest(http.MethodGet, "/api/auth/session", nil)
	authedSessionRequest.AddCookie(cookies[0])
	authedSessionRecorder := httptest.NewRecorder()
	handler.ServeHTTP(authedSessionRecorder, authedSessionRequest)
	if authedSessionRecorder.Code != http.StatusOK {
		t.Fatalf("expected authenticated session status 200, got %d", authedSessionRecorder.Code)
	}

	var sessionPayload responsePayload
	if err := json.Unmarshal(authedSessionRecorder.Body.Bytes(), &sessionPayload); err != nil {
		t.Fatalf("decode session payload: %v", err)
	}
	result, ok := sessionPayload.Result.(map[string]any)
	if !ok {
		t.Fatalf("expected session result object, got %#v", sessionPayload.Result)
	}
	if result["authenticated"] != true || result["loginRequired"] != true {
		t.Fatalf("unexpected session payload: %#v", result)
	}

	authedMountRequest := httptest.NewRequest(
		http.MethodPost,
		"/api/invoke/mount_bucket",
		strings.NewReader(`{"bucket":"demo"}`),
	)
	authedMountRequest.Header.Set("Content-Type", "application/json")
	authedMountRequest.AddCookie(cookies[0])
	authedMountRecorder := httptest.NewRecorder()
	handler.ServeHTTP(authedMountRecorder, authedMountRequest)
	if authedMountRecorder.Code != http.StatusOK {
		t.Fatalf("expected authenticated invoke status 200, got %d body=%s", authedMountRecorder.Code, authedMountRecorder.Body.String())
	}
	if !strings.Contains(authedMountRecorder.Body.String(), "/webdav/demo/") {
		t.Fatalf("expected mount response to contain WebDAV URL, got %s", authedMountRecorder.Body.String())
	}
}

func TestSaveConfigCreatesSessionForFirstRun(t *testing.T) {
	t.Setenv("HOME", t.TempDir())

	server := NewServer(Options{})
	handler := server.Handler()

	saveRequest := httptest.NewRequest(
		http.MethodPost,
		"/api/invoke/save_config",
		strings.NewReader(`{
			"config": {
				"endpoint": "https://example.invalid",
				"region": "auto",
				"bucket": "demo",
				"accessKeyId": "ak-test",
				"secretAccessKey": "sk-test",
				"usePathStyle": true
			}
		}`),
	)
	saveRequest.Header.Set("Content-Type", "application/json")
	saveRecorder := httptest.NewRecorder()
	handler.ServeHTTP(saveRecorder, saveRequest)
	if saveRecorder.Code != http.StatusOK {
		t.Fatalf("expected first-run save_config status 200, got %d body=%s", saveRecorder.Code, saveRecorder.Body.String())
	}

	response := saveRecorder.Result()
	cookies := response.Cookies()
	if len(cookies) == 0 {
		t.Fatal("expected save_config to create a session cookie for first-run web setup")
	}

	sessionRequest := httptest.NewRequest(http.MethodGet, "/api/auth/session", nil)
	sessionRequest.AddCookie(cookies[0])
	sessionRecorder := httptest.NewRecorder()
	handler.ServeHTTP(sessionRecorder, sessionRequest)
	if sessionRecorder.Code != http.StatusOK {
		t.Fatalf("expected authenticated session after first-run save_config, got %d", sessionRecorder.Code)
	}

	bucketsRequest := httptest.NewRequest(
		http.MethodPost,
		"/api/invoke/mount_bucket",
		strings.NewReader(`{"bucket":"demo"}`),
	)
	bucketsRequest.Header.Set("Content-Type", "application/json")
	bucketsRequest.AddCookie(cookies[0])
	bucketsRecorder := httptest.NewRecorder()
	handler.ServeHTTP(bucketsRecorder, bucketsRequest)
	if bucketsRecorder.Code != http.StatusOK {
		t.Fatalf("expected first-run session to unlock protected routes, got %d body=%s", bucketsRecorder.Code, bucketsRecorder.Body.String())
	}

	loginRequest := httptest.NewRequest(
		http.MethodPost,
		"/api/auth/login",
		strings.NewReader(`{"username":"ak-test","password":"sk-test"}`),
	)
	loginRequest.Header.Set("Content-Type", "application/json")
	loginRecorder := httptest.NewRecorder()
	handler.ServeHTTP(loginRecorder, loginRequest)
	if loginRecorder.Code != http.StatusOK {
		t.Fatalf("expected defaulted AK/SK WebDAV credentials to login successfully, got %d body=%s", loginRecorder.Code, loginRecorder.Body.String())
	}
}
