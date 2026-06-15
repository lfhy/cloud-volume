// Baidu OAuth helpers use the required OOB authorization-code flow.
package storage

import (
	"fmt"
	"log"
	"os/exec"
	"runtime"
	"strings"

	xpanauth "github.com/lfhy/xpan/auth"
	xpanclient "github.com/lfhy/xpan/client"
	xpanuser "github.com/lfhy/xpan/user"

	storageconfig "remote-storage/go/config"
)

const baiduPanOAuthRedirectURI = "oob"

// StartBaiduPanAuthorization opens the browser to Baidu's OOB authorization page
// and returns the exact URL so the UI can surface it if the browser fails to open.
func StartBaiduPanAuthorization() (string, error) {
	authURL := baiduPanAuthURL()
	if err := openBaiduPanBrowser(authURL); err != nil {
		log.Printf("[storage/baidu-pan] oauth browser open failed: %v", err)
	}
	return authURL, nil
}

// AuthorizeBaiduPanWithCode exchanges a user-pasted OOB authorization code for tokens.
func AuthorizeBaiduPanWithCode(
	displayName string,
	code string,
) (storageconfig.RemoteStorageConfig, error) {
	trimmedCode := strings.TrimSpace(code)
	if trimmedCode == "" {
		return storageconfig.RemoteStorageConfig{}, fmt.Errorf("百度网盘授权码不能为空")
	}

	baiduPanSDKMu.Lock()
	defer baiduPanSDKMu.Unlock()

	client := xpanclient.New(&xpanauth.AuthEnv{
		ClientId:     baiduPanClientID,
		ClientSecret: baiduPanClientSecret,
		RedirectUri:  baiduPanOAuthRedirectURI,
	})
	token, err := client.GetToken(trimmedCode, baiduPanOAuthRedirectURI)
	if err != nil {
		return storageconfig.RemoteStorageConfig{}, err
	}
	userInfo, err := xpanuser.GetUserInfo(&xpanuser.UserInfoReq{})
	if err != nil {
		return storageconfig.RemoteStorageConfig{}, err
	}
	label := strings.TrimSpace(displayName)
	if label == "" {
		label = strings.TrimSpace(userInfo.NetDiskName)
	}
	if label == "" {
		label = strings.TrimSpace(userInfo.BaiduName)
	}
	if label == "" {
		label = "百度网盘"
	}
	cfg := baiduPanConfigFromAuth(label, token.AccessToken, token.RefreshToken)
	rememberBaiduPanState(
		baiduPanSessionKeys(cfg, baiduPanAuthState{
			accessToken:  token.AccessToken,
			refreshToken: token.RefreshToken,
		}),
		baiduPanAuthState{
			accessToken:  token.AccessToken,
			refreshToken: token.RefreshToken,
		},
	)
	return cfg, nil
}

func baiduPanAuthURL() string {
	client := xpanclient.New()
	return client.GetAuthCodeURL(&xpanauth.AuthCodeReq{
		ClientId:    baiduPanClientID,
		RedirectUri: baiduPanOAuthRedirectURI,
	})
}

func openBaiduPanBrowser(targetURL string) error {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", targetURL)
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", targetURL)
	default:
		cmd = exec.Command("xdg-open", targetURL)
	}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("open browser for oauth: %w", err)
	}
	return nil
}
