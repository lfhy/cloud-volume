// Interactive shell mode keeps repeated CLI operations short on headless servers.
package main

import (
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/peterh/liner"
	s3ops "remote-storage/go/s3"
)

var errShellExit = errors.New("shell exit")

type shellState struct {
	configPath     string
	bucketOverride string
	currentDir     string
	editor         *shellEditor
}

var activeShell *shellState

func runShell() error {
	loaded, err := loadConfig("")
	if err != nil {
		return err
	}
	state := &shellState{
		configPath: loaded.path,
	}
	activeShell = state
	defer func() {
		activeShell = nil
	}()

	if strings.TrimSpace(loaded.cfg.Bucket) != "" {
		state.bucketOverride = strings.TrimSpace(loaded.cfg.Bucket)
	}

	fmt.Fprintln(stdoutWriter(), "输入 help 查看命令，输入 exit 退出。")

	editor, err := newShellEditor(state)
	if err != nil {
		return err
	}
	state.editor = editor
	defer func() {
		_ = editor.Close()
		state.editor = nil
	}()

	if loaded.cfg.IsConfigured() && strings.TrimSpace(state.bucketOverride) == "" {
		if err := ensureShellBucketSelected(state, loaded); err != nil {
			return err
		}
	}

	for {
		line, err := editor.Prompt(shellPrompt(state))
		if err != nil {
			if errors.Is(err, liner.ErrPromptAborted) {
				fmt.Fprintln(stdoutWriter())
				continue
			}
			if strings.Contains(strings.ToLower(err.Error()), "eof") {
				fmt.Fprintln(stdoutWriter())
				return nil
			}
			return nil
		}
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		args, err := splitShellLine(line)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			continue
		}
		if err := runShellCommand(state, args); err != nil {
			if errors.Is(err, errShellExit) {
				return nil
			}
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			continue
		}
		editor.AppendHistory(line)
	}
}

func ensureShellBucketSelected(state *shellState, loaded loadedConfig) error {
	if state == nil {
		return errors.New("shell state is not initialized")
	}
	if strings.TrimSpace(state.bucketOverride) != "" {
		return nil
	}
	selected, err := chooseBucketInteractively(loaded)
	if err != nil {
		return err
	}
	applySelectedBucket(selected)
	return nil
}

func shellPrompt(state *shellState) string {
	if state != nil {
		dir := shellDisplayDir(state.currentDir)
		bucket := strings.TrimSpace(state.bucketOverride)
		if bucket == "" {
			bucket = "no-bucket"
		}
		return fmt.Sprintf("cloud-volume[%s:%s]> ", bucket, dir)
	}
	return "cloud-volume> "
}

func runShellCommand(state *shellState, args []string) error {
	if len(args) == 0 {
		return nil
	}
	switch strings.ToLower(strings.TrimSpace(args[0])) {
	case "init":
		return runShellInitCommand(state, args[1:])
	case "exit", "quit":
		return errShellExit
	case "bucket":
		return runShellBucketCommand(state, args[1:])
	case "cd":
		return runShellCDCommand(state, args[1:])
	case "pwd":
		return runShellPWDCommand(state, args[1:])
	case "?":
		printShellHelp()
		return nil
	default:
		return run(args)
	}
}

func runShellInitCommand(state *shellState, args []string) error {
	if state == nil || state.editor == nil {
		return runInitCommand(args)
	}
	if err := state.editor.Suspend(); err != nil {
		return err
	}
	defer func() {
		_ = state.editor.Resume(state)
	}()
	return runInitCommand(args)
}

func runShellBucketCommand(state *shellState, args []string) error {
	if state == nil {
		return errors.New("shell state is not initialized")
	}
	return runBucketCommand(args)
}

func runShellCDCommand(state *shellState, args []string) error {
	if state == nil {
		return errors.New("shell state is not initialized")
	}
	if len(args) > 1 {
		return errors.New("cd 用法: cd [remote-dir]")
	}
	if strings.TrimSpace(state.bucketOverride) == "" {
		return errors.New("请先设置 bucket，再执行 cd")
	}

	targetDir := ""
	if len(args) == 1 {
		targetDir = resolveVisiblePath(state.currentDir, args[0])
	}
	if err := ensureRemoteDirectoryExists(state, targetDir); err != nil {
		return err
	}
	state.currentDir = targetDir
	fmt.Fprintln(stdoutWriter(), shellDisplayDir(state.currentDir))
	return nil
}

func runShellPWDCommand(state *shellState, args []string) error {
	if len(args) != 0 {
		return errors.New("pwd 不接受参数")
	}
	if state == nil {
		return errors.New("shell state is not initialized")
	}
	fmt.Fprintln(stdoutWriter(), shellDisplayDir(state.currentDir))
	return nil
}

func ensureRemoteDirectoryExists(state *shellState, visibleDir string) error {
	loaded, err := loadConfiguredConfig(state.configPath)
	if err != nil {
		return err
	}
	prefix := applyRootPrefix(loaded.cfg.RootPrefix, visibleDir, true)
	if prefix == "" {
		return nil
	}
	page, err := s3ops.ListObjectsPage(loaded.cfg, state.bucketOverride, prefix, "", 1)
	if err != nil {
		return err
	}
	if len(page.Items) > 0 {
		return nil
	}
	if _, err := s3ops.HeadObject(loaded.cfg, state.bucketOverride, strings.TrimSuffix(prefix, "/")); err == nil {
		return fmt.Errorf("%s 不是目录", shellDisplayDir(visibleDir))
	}
	if _, err := s3ops.HeadObject(loaded.cfg, state.bucketOverride, prefix); err == nil {
		return nil
	}
	return fmt.Errorf("远端目录不存在: %s", shellDisplayDir(visibleDir))
}

func printShellHelp() {
	printUsage(stdoutWriter())
	fmt.Fprintln(stdoutWriter(), "")
	fmt.Fprintln(stdoutWriter(), "Shell builtins:")
	fmt.Fprintln(stdoutWriter(), "  bucket           弹出 bucket 选择器并切换当前 bucket")
	fmt.Fprintln(stdoutWriter(), "  bucket list      列出可用 bucket")
	fmt.Fprintln(stdoutWriter(), "  bucket <name>    直接切换当前 bucket")
	fmt.Fprintln(stdoutWriter(), "  cd [dir]         切换当前远端目录，支持相对路径、.. 和绝对路径")
	fmt.Fprintln(stdoutWriter(), "  pwd              输出当前远端目录")
	fmt.Fprintln(stdoutWriter(), "  Tab              远端路径和命令补全")
	fmt.Fprintln(stdoutWriter(), "  Up/Down          历史记录，保存在 ~/.remote-storage/runtime/cli_history")
	fmt.Fprintln(stdoutWriter(), "  exit | quit      退出 shell")
}

func shellDisplayDir(value string) string {
	clean := cleanObjectPath(value)
	if clean == "" {
		return "/"
	}
	return "/" + clean
}

func currentShellDir() string {
	if activeShell == nil {
		return ""
	}
	return cleanObjectPath(activeShell.currentDir)
}
