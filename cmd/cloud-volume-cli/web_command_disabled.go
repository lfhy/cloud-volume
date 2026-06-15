//go:build !cli_full

// Lite CLI builds keep the web runtime out of the binary on purpose.
package main

import "errors"

func cliDisplayName() string {
	return "cloud-volume-cli"
}

func cliSupportsEmbeddedWeb() bool {
	return false
}

func runWebCommand(args []string) error {
	_ = args
	return errors.New("当前 cloud-volume-cli 为 lite 版本，不包含 web 子命令；请下载 cloud-volume-cli-full")
}
