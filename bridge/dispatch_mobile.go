package main

import (
	"encoding/json"
	"fmt"
	"strings"

	storageconfig "remote-storage/go/config"
)

// Mobile hosts set a private writable root before invoking config-backed APIs.
func setAppDataRoot(args json.RawMessage) (map[string]string, error) {
	var input struct {
		Path string `json:"path"`
	}
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageconfig.SetAppDataRoot(input.Path); err != nil {
		return nil, fmt.Errorf("set app data root: %w", err)
	}
	return map[string]string{"path": strings.TrimSpace(input.Path)}, nil
}
