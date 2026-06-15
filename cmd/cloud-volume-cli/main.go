// cloud-volume-cli provides a Linux-friendly CLI entrypoint for config and mounts.
package main

import (
	"fmt"
	"os"
)

var version = "dev"

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
}
