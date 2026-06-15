// Shell editor integration provides persistent history and tab completion.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"github.com/peterh/liner"

	storageconfig "remote-storage/go/config"
)

type shellEditor struct {
	line        *liner.State
	historyPath string
	mu          sync.Mutex
}

func newShellEditor(state *shellState) (*shellEditor, error) {
	line := liner.NewLiner()
	line.SetCtrlCAborts(true)
	line.SetCompleter(func(input string) []string {
		return completeShellInput(state, input)
	})

	editor := &shellEditor{
		line:        line,
		historyPath: shellHistoryPath(),
	}
	if err := editor.loadHistory(); err != nil {
		line.Close()
		return nil, err
	}
	return editor, nil
}

func (e *shellEditor) Close() error {
	if e == nil || e.line == nil {
		return nil
	}
	defer e.line.Close()
	return e.saveHistory()
}

func (e *shellEditor) Prompt(prompt string) (string, error) {
	if e == nil || e.line == nil {
		return "", fmt.Errorf("shell editor is not initialized")
	}
	return e.line.Prompt(prompt)
}

func (e *shellEditor) AppendHistory(line string) {
	if e == nil || e.line == nil {
		return
	}
	trimmed := strings.TrimSpace(line)
	if trimmed == "" {
		return
	}
	e.line.AppendHistory(trimmed)
}

func (e *shellEditor) Suspend() error {
	if e == nil {
		return nil
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.line == nil {
		return nil
	}
	if err := e.saveHistory(); err != nil {
		return err
	}
	e.line.Close()
	e.line = nil
	return nil
}

func (e *shellEditor) Resume(state *shellState) error {
	if e == nil {
		return nil
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.line != nil {
		return nil
	}
	line := liner.NewLiner()
	line.SetCtrlCAborts(true)
	line.SetCompleter(func(input string) []string {
		return completeShellInput(state, input)
	})
	e.line = line
	return e.loadHistory()
}

func (e *shellEditor) loadHistory() error {
	if e == nil || e.line == nil || strings.TrimSpace(e.historyPath) == "" {
		return nil
	}
	file, err := os.Open(e.historyPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	defer file.Close()
	_, err = e.line.ReadHistory(file)
	return err
}

func (e *shellEditor) saveHistory() error {
	if e == nil || e.line == nil || strings.TrimSpace(e.historyPath) == "" {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(e.historyPath), 0o700); err != nil {
		return err
	}
	file, err := os.Create(e.historyPath)
	if err != nil {
		return err
	}
	defer file.Close()
	_, err = e.line.WriteHistory(file)
	return err
}

func shellHistoryPath() string {
	runtimeDir, err := storageconfig.RuntimeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(runtimeDir, "cli_history")
}

func completeShellInput(state *shellState, input string) []string {
	args, trailingSpace, err := splitShellLineWithState(input)
	if err != nil {
		return nil
	}
	if len(args) == 0 {
		return commandCandidates("", input)
	}
	command := strings.ToLower(strings.TrimSpace(args[0]))
	switch {
	case len(args) == 1 && !trailingSpace:
		return commandCandidates(args[0], input)
	case command == "bucket":
		return nil
	case command == "cd" || command == "ls" || command == "list" || command == "get" || command == "rm" || command == "delete":
		return completeRemotePathArgs(state, args, trailingSpace, input, command != "get" && command != "rm" && command != "delete")
	case command == "mkdir":
		return completeRemotePathArgs(state, args, trailingSpace, input, true)
	case command == "put":
		return completePutArgs(state, args, trailingSpace, input)
	default:
		return nil
	}
}

func commandCandidates(prefix, rawInput string) []string {
	commands := []string{
		"help", "shell", "init", "put", "get", "mkdir", "rm", "delete",
		"ls", "list", "mount", "unmount", "status", "version",
		"bucket", "cd", "pwd", "exit", "quit",
	}
	matches := make([]string, 0)
	for _, command := range commands {
		if strings.HasPrefix(command, strings.ToLower(prefix)) {
			matches = append(matches, command)
		}
	}
	sort.Strings(matches)
	return rewriteCompletionPrefix(rawInput, prefix, matches)
}

func completeRemotePathArgs(state *shellState, args []string, trailingSpace bool, rawInput string, directoriesOnly bool) []string {
	token := ""
	if trailingSpace {
		token = ""
	} else if len(args) > 0 {
		token = args[len(args)-1]
	}
	candidates, err := remotePathCompletions(state, token, directoriesOnly)
	if err != nil {
		return nil
	}
	return rewriteCompletionPrefix(rawInput, token, candidates)
}

func completePutArgs(state *shellState, args []string, trailingSpace bool, rawInput string) []string {
	if len(args) <= 1 || (len(args) == 2 && !trailingSpace) {
		return nil
	}
	token := ""
	if !trailingSpace && len(args) > 0 {
		token = args[len(args)-1]
	}
	candidates, err := remotePathCompletions(state, token, false)
	if err != nil {
		return nil
	}
	return rewriteCompletionPrefix(rawInput, token, candidates)
}

func remotePathCompletions(state *shellState, token string, directoriesOnly bool) ([]string, error) {
	if state == nil || strings.TrimSpace(state.bucketOverride) == "" {
		return nil, nil
	}
	loaded, err := loadConfiguredConfig(state.configPath)
	if err != nil {
		return nil, err
	}

	baseDir := currentShellDir()
	searchToken := strings.TrimSpace(token)
	visibleSearch := resolveVisiblePath(baseDir, searchToken)
	parent := parentObjectDir(visibleSearch)
	prefix := baseDir
	if searchToken != "" && !strings.HasSuffix(searchToken, "/") {
		prefix = parent
	}
	items, err := listVisibleObjects(loaded, state.bucketOverride, prefix)
	if err != nil {
		return nil, err
	}
	candidates := make([]string, 0, len(items))
	for _, item := range items {
		if directoriesOnly && !item.IsDir {
			continue
		}
		candidate := item.Key
		if prefix != "" {
			candidate = resolveVisiblePath(prefix, candidate)
		}
		if !strings.HasPrefix(candidate, visibleSearch) {
			continue
		}
		display := candidate
		if item.IsDir {
			display = ensureObjectDirSuffix(display)
		}
		candidates = append(candidates, display)
	}
	sort.Strings(candidates)
	return candidates, nil
}

func rewriteCompletionPrefix(rawInput, token string, candidates []string) []string {
	if len(candidates) == 0 {
		return nil
	}
	index := strings.LastIndex(rawInput, token)
	if strings.TrimSpace(token) == "" || index < 0 {
		return candidates
	}
	prefix := rawInput[:index]
	rewritten := make([]string, 0, len(candidates))
	for _, candidate := range candidates {
		rewritten = append(rewritten, prefix+candidate)
	}
	return rewritten
}
