// Baidu Pan bridge methods keep the desktop OAuth loop inside the Go layer.
package main

import (
	"encoding/json"

	storageconfig "remote-storage/go/config"
	storageops "remote-storage/go/storage"
)

type baiduPanAuthorizeArgs struct {
	DisplayName string `json:"displayName"`
	Code        string `json:"code"`
}

func startBaiduPanAuthorization() (any, error) {
	authURL, err := storageops.StartBaiduPanAuthorization()
	if err != nil {
		return map[string]any{"authUrl": authURL}, err
	}
	return map[string]any{"authUrl": authURL}, nil
}

func authorizeBaiduPan(args json.RawMessage) (any, error) {
	var input baiduPanAuthorizeArgs
	if len(args) > 0 {
		if err := decodeArgs(args, &input); err != nil {
			return nil, err
		}
	}
	config, err := storageops.AuthorizeBaiduPanWithCode(
		input.DisplayName,
		input.Code,
	)
	if err != nil {
		return nil, err
	}
	publicConfig, err := config.WithResolvedCacheDirectory()
	if err != nil {
		return storageconfig.RemoteStorageConfig{}, err
	}
	return publicConfig, nil
}
