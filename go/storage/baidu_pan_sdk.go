// Baidu Pan SDK helpers centralize OAuth token reuse around the xpan globals.
package storage

import (
	"errors"
	"strings"
	"sync"

	xpanauth "github.com/lfhy/xpan/auth"
	xpanclient "github.com/lfhy/xpan/client"
	xpanhttp "github.com/lfhy/xpan/http"
	xpantypes "github.com/lfhy/xpan/types"

	storageconfig "remote-storage/go/config"
)

const (
	baiduPanClientID     = "LXSNsyO78fe6j3RkXsY0UBhC191P4RW6"
	baiduPanClientSecret = "2FdwKMRizTw45rnMS4fon22hHa1ZIRQz"
	baiduPanEndpoint     = "https://pan.baidu.com"
	baiduPanUploadRoot   = "/apps/网盘demo"
)

type baiduPanAuthState struct {
	accessToken  string
	refreshToken string
}

var (
	baiduPanSDKMu    sync.Mutex
	baiduPanSessions sync.Map
)

func init() {
	// Keep one reusable HTTP client for SDK calls and retry transient upstream throttling.
	xpanhttp.SetClient(newBaiduPanRetryHTTPClient())
	// The SDK's conservative default rate limit is too low for 4 MB upload chunks.
	xpanhttp.SetRateLimitEnabled(false)
}

func baiduPanConfigFromAuth(
	displayName string,
	accessToken string,
	refreshToken string,
) storageconfig.RemoteStorageConfig {
	cfg := storageconfig.DefaultConfig()
	cfg.Endpoint = baiduPanEndpoint
	cfg.StorageType = storageconfig.StorageTypeBaiduPan
	cfg.ProviderType = storageconfig.StorageTypeBaiduPan
	cfg.DisplayName = strings.TrimSpace(displayName)
	cfg.MappedBucketName = strings.TrimSpace(displayName)
	cfg.AccessKeyID = strings.TrimSpace(accessToken)
	cfg.SecretAccessKey = strings.TrimSpace(refreshToken)
	cfg.HasSecretAccessKey = cfg.SecretAccessKey != ""
	return cfg.Normalized()
}

func baiduPanBucketLabel(cfg storageconfig.RemoteStorageConfig) string {
	label := strings.TrimSpace(cfg.MappedBucketLabel())
	if label != "" {
		return label
	}
	if name := strings.TrimSpace(cfg.DisplayName); name != "" {
		return name
	}
	return "百度网盘"
}

func withBaiduPanClient[T any](
	cfg storageconfig.RemoteStorageConfig,
	fn func(*xpanclient.Client) (T, error),
) (T, error) {
	var zero T

	baiduPanSDKMu.Lock()
	state := baiduPanStateForConfig(cfg)
	baiduPanSDKMu.Unlock()

	client := baiduPanClientForState(state)
	result, err := fn(client)
	if err == nil || !shouldRefreshBaiduPanToken(err) || state.refreshToken == "" {
		return result, err
	}
	baiduPanSDKMu.Lock()
	refreshed, refreshErr := refreshBaiduPanStateLocked(state)
	if refreshErr != nil {
		baiduPanSDKMu.Unlock()
		return zero, err
	}
	rememberBaiduPanState(baiduPanSessionKeys(cfg, state), refreshed)
	persistBaiduPanState(cfg, refreshed)
	baiduPanSDKMu.Unlock()
	return fn(baiduPanClientForState(refreshed))
}

func baiduPanStateForConfig(cfg storageconfig.RemoteStorageConfig) baiduPanAuthState {
	keys := baiduPanSessionKeys(
		cfg,
		baiduPanAuthState{
			accessToken:  cfg.AccessKeyID,
			refreshToken: cfg.SecretAccessKey,
		},
	)
	for _, key := range keys {
		if value, ok := baiduPanSessions.Load(key); ok {
			if state, valid := value.(baiduPanAuthState); valid {
				return state
			}
		}
	}
	return baiduPanAuthState{
		accessToken:  strings.TrimSpace(cfg.AccessKeyID),
		refreshToken: strings.TrimSpace(cfg.SecretAccessKey),
	}
}

func baiduPanClientForState(state baiduPanAuthState) *xpanclient.Client {
	return xpanclient.New(&xpanauth.AuthEnv{
		ClientId:     baiduPanClientID,
		ClientSecret: baiduPanClientSecret,
		AccessToken:  state.accessToken,
		RefreshToken: state.refreshToken,
	})
}

func refreshBaiduPanStateLocked(
	current baiduPanAuthState,
) (baiduPanAuthState, error) {
	client := baiduPanClientForState(current)
	res, err := client.RefreshToken()
	if err != nil {
		return baiduPanAuthState{}, err
	}
	next := baiduPanAuthState{
		accessToken:  strings.TrimSpace(res.AccessToken),
		refreshToken: strings.TrimSpace(res.RefreshToken),
	}
	if next.refreshToken == "" {
		next.refreshToken = current.refreshToken
	}
	return next, nil
}

func rememberBaiduPanState(keys []string, state baiduPanAuthState) {
	for _, key := range keys {
		if strings.TrimSpace(key) == "" {
			continue
		}
		baiduPanSessions.Store(key, state)
	}
}

func baiduPanSessionKeys(
	cfg storageconfig.RemoteStorageConfig,
	state baiduPanAuthState,
) []string {
	keys := []string{
		"refresh:" + strings.TrimSpace(state.refreshToken),
		"access:" + strings.TrimSpace(state.accessToken),
		"profile:" + strings.TrimSpace(cfg.DisplayName) + "|" + strings.TrimSpace(cfg.Endpoint),
	}
	filtered := make([]string, 0, len(keys))
	for _, key := range keys {
		if strings.HasSuffix(key, ":") || strings.HasSuffix(key, "|") {
			continue
		}
		filtered = append(filtered, key)
	}
	return filtered
}

func persistBaiduPanState(
	cfg storageconfig.RemoteStorageConfig,
	state baiduPanAuthState,
) {
	activeName, err := storageconfig.ActiveProfileName()
	if err != nil {
		return
	}
	current, err := storageconfig.LoadProfile(activeName)
	if err != nil {
		return
	}
	current = current.Normalized()
	base := cfg.Normalized()
	if current.StorageType != storageconfig.StorageTypeBaiduPan ||
		current.StorageType != base.StorageType ||
		current.DisplayName != base.DisplayName ||
		current.Endpoint != base.Endpoint {
		return
	}
	current.AccessKeyID = state.accessToken
	current.SecretAccessKey = state.refreshToken
	current.HasSecretAccessKey = state.refreshToken != ""
	_ = storageconfig.SaveProfile(activeName, current)
}

func shouldRefreshBaiduPanToken(err error) bool {
	if err == nil {
		return false
	}
	var apiErr xpantypes.Error
	if errors.As(err, &apiErr) {
		if strings.TrimSpace(apiErr.AuthError) != "" {
			return true
		}
		text := strings.ToLower(apiErr.Error())
		if strings.Contains(text, "token") || strings.Contains(text, "expired") {
			return true
		}
	}
	text := strings.ToLower(err.Error())
	return strings.Contains(text, "token") ||
		strings.Contains(text, "expired") ||
		strings.Contains(text, "invalid")
}
