//go:build cli_full

// Full CLI builds embed the Flutter web bundle so one binary can host the web console.
package main

import (
	"embed"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"remote-storage/go/webapi"
)

//go:embed embedded_web/*
var embeddedWebAssets embed.FS

func cliDisplayName() string {
	return "cloud-volume-cli-full"
}

func cliSupportsEmbeddedWeb() bool {
	return true
}

func runWebCommand(args []string) error {
	if len(args) > 0 {
		switch strings.ToLower(strings.TrimSpace(args[0])) {
		case "version", "--version":
			fmt.Fprintln(os.Stdout, version)
			return nil
		}
	}
	flags := newFlagSet("web")
	listenAddr := flags.String("listen", ":8080", "HTTP listen address")
	staticRoot := flags.String("static-root", filepath.Join("build", "web"), "Flutter web build directory")
	if err := flags.Parse(args); err != nil {
		return err
	}
	assetFS, err := fs.Sub(embeddedWebAssets, "embedded_web")
	if err != nil {
		return err
	}
	return serveWeb(webapi.Options{StaticRoot: *staticRoot, StaticFS: assetFS}, *listenAddr)
}
