// Web entrypoint serves the Flutter web build, JSON API, and WebDAV endpoints.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"remote-storage/go/webapi"
)

var version = "dev"

func main() {
	if len(os.Args) > 1 {
		switch strings.ToLower(strings.TrimSpace(os.Args[1])) {
		case "version", "--version":
			fmt.Fprintln(os.Stdout, version)
			return
		}
	}
	listenAddr := flag.String("listen", ":8080", "HTTP listen address")
	staticRoot := flag.String("static-root", filepath.Join("build", "web"), "Flutter web build directory")
	flag.Parse()
	if err := serveWeb(webapi.Options{StaticRoot: *staticRoot}, *listenAddr); err != nil {
		panic(err)
	}
}
