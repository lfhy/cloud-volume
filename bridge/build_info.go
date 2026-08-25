package main

import "runtime"

var buildArch = ""

type buildInfoResult struct {
	BuildArch   string `json:"buildArch"`
	RuntimeOS   string `json:"runtimeOS"`
	RuntimeArch string `json:"runtimeArch"`
}

// getBuildInfo returns compile-time metadata embedded by release scripts.
func getBuildInfo() (buildInfoResult, error) {
	arch := buildArch
	if arch == "" {
		arch = runtime.GOARCH
	}
	return buildInfoResult{
		BuildArch:   arch,
		RuntimeOS:   runtime.GOOS,
		RuntimeArch: runtime.GOARCH,
	}, nil
}
