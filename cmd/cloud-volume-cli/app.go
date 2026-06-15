// Command routing is kept in one file so subcommands stay easy to discover.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
)

func run(args []string) error {
	if len(args) == 0 {
		return runShell()
	}

	switch strings.ToLower(strings.TrimSpace(args[0])) {
	case "help", "-h", "--help":
		printUsage(os.Stdout)
		return nil
	case "version", "--version":
		fmt.Fprintln(os.Stdout, version)
		return nil
	case "init":
		return runInitCommand(args[1:])
	case "shell":
		return runShell()
	case "mount":
		return runMountCommand(args[1:])
	case "unmount":
		return runUnmountCommand(args[1:])
	case "status":
		return runStatusCommand(args[1:])
	case "put":
		return runPutCommand(args[1:])
	case "get":
		return runGetCommand(args[1:])
	case "bucket":
		return runBucketCommand(args[1:])
	case "mkdir":
		return runMkdirCommand(args[1:])
	case "rm", "delete":
		return runRemoveCommand(args[1:])
	case "list", "ls":
		return runListCommand(args[1:])
	case "web":
		return runWebCommand(args[1:])
	default:
		printUsage(os.Stderr)
		return fmt.Errorf("unknown command %q", args[0])
	}
}

func newFlagSet(name string) *flag.FlagSet {
	set := flag.NewFlagSet(name, flag.ContinueOnError)
	set.SetOutput(io.Discard)
	return set
}

func printUsage(w io.Writer) {
	commandName := cliDisplayName()
	fmt.Fprintln(w, "Usage:")
	fmt.Fprintf(w, "  %s                    # enter interactive shell\n", commandName)
	fmt.Fprintf(w, "  %s shell\n", commandName)
	fmt.Fprintf(w, "  %s init [--config /path/to/config.toml] [--skip-validate]\n", commandName)
	fmt.Fprintf(w, "  %s bucket [list|<name>]\n", commandName)
	fmt.Fprintf(w, "  %s put [--config /path/to/config.toml] [--bucket name] <local-path> [remote-path]\n", commandName)
	fmt.Fprintf(w, "  %s get [--config /path/to/config.toml] [--bucket name] <remote-path> [local-path]\n", commandName)
	fmt.Fprintf(w, "  %s mkdir [--config /path/to/config.toml] [--bucket name] <remote-dir>\n", commandName)
	fmt.Fprintf(w, "  %s rm [--config /path/to/config.toml] [--bucket name] <remote-path>\n", commandName)
	fmt.Fprintf(w, "  %s delete [--config /path/to/config.toml] [--bucket name] <remote-path>\n", commandName)
	fmt.Fprintf(w, "  %s ls [--config /path/to/config.toml] [--bucket name] [prefix]\n", commandName)
	fmt.Fprintf(w, "  %s list [--config /path/to/config.toml] [--bucket name] [prefix]\n", commandName)
	fmt.Fprintf(w, "  %s mount [--config /path/to/config.toml] [--bucket name] [--mount-point /path]\n", commandName)
	fmt.Fprintf(w, "  %s unmount [--config /path/to/config.toml] [--bucket name] [--mount-point /path]\n", commandName)
	fmt.Fprintf(w, "  %s status [--config /path/to/config.toml] [--bucket name] [--mount-point /path]\n", commandName)
	if cliSupportsEmbeddedWeb() {
		fmt.Fprintf(w, "  %s web [--listen :8080] [--static-root build/web]\n", commandName)
	}
	fmt.Fprintf(w, "  %s version\n", commandName)
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "Examples:")
	fmt.Fprintf(w, "  %s init\n", commandName)
	fmt.Fprintf(w, "  %s bucket list\n", commandName)
	fmt.Fprintf(w, "  %s put ./demo.txt docs/demo.txt\n", commandName)
	fmt.Fprintf(w, "  %s get docs/demo.txt ./demo.txt\n", commandName)
	fmt.Fprintf(w, "  %s mkdir docs/archive\n", commandName)
	fmt.Fprintf(w, "  %s rm docs/archive\n", commandName)
	fmt.Fprintf(w, "  %s ls docs\n", commandName)
	fmt.Fprintf(w, "  %s mount --bucket media --mount-point /mnt/media\n", commandName)
	fmt.Fprintf(w, "  %s status --bucket media\n", commandName)
	fmt.Fprintf(w, "  %s unmount --bucket media\n", commandName)
	if cliSupportsEmbeddedWeb() {
		fmt.Fprintf(w, "  %s web --listen :8080\n", commandName)
	}
}
