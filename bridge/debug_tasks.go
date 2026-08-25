// Optional localhost debug endpoint exposing live metadata-task runtime state.
// Start it by setting CV_DEBUG_ADDR (e.g. "127.0.0.1:8765"); unset = off.
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"sync"
	"time"

	bucketmetadata "remote-storage/go/mount/metadata"
	s3ops "remote-storage/go/s3"

	"golang.org/x/net/websocket"
)

var debugListenOnce sync.Once

// startTaskDebugListener lazily boots the debug server on the first bridge
// call so a c-shared library never spawns sockets during dylib load.
func startTaskDebugListener() {
	debugListenOnce.Do(func() {
		addr := os.Getenv("CV_DEBUG_ADDR")
		if addr == "" {
			return
		}
		if !isLoopbackDebugAddr(addr) {
			log.Printf("[bridge/debug] refusing non-loopback CV_DEBUG_ADDR=%q", addr)
			return
		}
		listener, err := net.Listen("tcp", addr)
		if err != nil {
			log.Printf("[bridge/debug] listen %s failed: %v", addr, err)
			return
		}
		mux := http.NewServeMux()
		mux.HandleFunc("/debug/tasks", handleDebugTasks)
		mux.HandleFunc("/debug/transfers", handleDebugTransfers)
		// Push channel: metadata workers tick this socket on every op state
		// change so the task page can re-fetch immediately instead of polling.
		mux.Handle("/debug/task-events", websocket.Handler(handleTaskEvents))
		go func() {
			log.Printf("[bridge/debug] serving on http://%s/debug/tasks (ws: /debug/task-events)", addr)
			_ = http.Serve(listener, mux)
		}()
	})
}

// isLoopbackDebugAddr rejects wildcard and LAN bindings: task diagnostics may
// expose object paths and errors, so this listener is strictly local-only.
func isLoopbackDebugAddr(addr string) bool {
	host, port, err := net.SplitHostPort(addr)
	if err != nil || port == "" {
		return false
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

// handleTaskEvents streams one JSON tick per metadata op state change. The
// payload is intentionally minimal ("changed"); the client re-fetches the
// list over its existing API. Signal coalescing happens naturally through
// the buffered channel, so a burst of completions costs one refresh.
func handleTaskEvents(ws *websocket.Conn) {
	defer ws.Close()
	manager, err := bucketmetadata.DefaultManager()
	if err != nil {
		_ = websocket.Message.Send(ws, `{"error":"`+err.Error()+`"}`)
		return
	}
	changes, stop := manager.SubscribeTaskChanges()
	defer stop()
	// Read until the peer closes so a disposed Dart WebSocket unregisters its
	// manager subscription even when no task changes happen afterward.
	disconnected := taskEventsDisconnected(ws)
	_ = websocket.Message.Send(ws, `{"event":"hello"}`)
	for {
		select {
		case <-disconnected:
			return
		case _, open := <-changes:
			if !open {
				return
			}
			if err := websocket.Message.Send(ws, `{"event":"changed"}`); err != nil {
				return
			}
		}
	}
}

// taskEventsDisconnected observes the read side while handleTaskEvents writes
// ticks; one reader and one writer are safe on the underlying net connection.
func taskEventsDisconnected(ws *websocket.Conn) <-chan struct{} {
	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			var ignored string
			if err := websocket.Message.Receive(ws, &ignored); err != nil {
				return
			}
		}
	}()
	return done
}

// handleDebugTasks dumps every namespace's task projection including
// lastError / retry / nextRetryAt so a stuck "verifying" queue can be
// diagnosed against live runtime data instead of guesses.
func handleDebugTasks(w http.ResponseWriter, r *http.Request) {
	manager, err := bucketmetadata.DefaultManager()
	if err != nil {
		writeDebugJSON(w, map[string]any{"error": err.Error()})
		return
	}
	// Debugging must inspect retained namespaces even when no page/mount currently
	// holds one open; otherwise a post-restart request falsely reports zero tasks.
	handles, err := warmKnownTaskNamespaces(manager, remoteTaskListArgs{})
	if err != nil {
		writeDebugJSON(w, map[string]any{"error": err.Error()})
		return
	}
	defer releaseTaskNamespaceHandles(manager, handles)
	groups, err := manager.ListTaskGroups()
	if err != nil {
		writeDebugJSON(w, map[string]any{"error": err.Error()})
		return
	}
	namespaces := make([]any, 0, len(groups))
	for _, group := range groups {
		tasks := make([]any, 0, len(group.Tasks))
		for _, task := range group.Tasks {
			tasks = append(tasks, map[string]any{
				"id": task.ID, "kind": task.Kind, "state": string(task.State),
				"status": task.Status, "phase": task.Phase,
				"sourcePath": task.SourcePath, "targetPath": task.TargetPath,
				"lastError": task.LastError, "retry": task.Retry,
				"nextRetryAt": task.NextRetryAt, "seq": task.Seq,
				"createdAt": task.CreatedAt, "updatedAt": task.UpdatedAt,
			})
		}
		summary := map[string]any{
			"total":   group.Summary.Total,
			"pending": group.Summary.Pending,
			"running": group.Summary.Running,
			"blocked": group.Summary.Blocked,
			"failed":  group.Summary.Failed,
		}
		namespaces = append(namespaces, map[string]any{
			"namespace": group.Namespace, "summary": summary, "tasks": tasks,
		})
	}
	writeDebugJSON(w, map[string]any{
		"serverTime": time.Now().UTC().Format(time.RFC3339Nano),
		"namespaces": namespaces,
	})
}

// handleDebugTransfers dumps the runtime transfer monitor so physical
// uploads behind metadata tasks can be checked alongside journal state.
func handleDebugTransfers(w http.ResponseWriter, r *http.Request) {
	snapshots := s3ops.ListTransferSnapshots()
	items := make([]any, 0, len(snapshots))
	for _, snapshot := range snapshots {
		items = append(items, map[string]any{
			"id": snapshot.ID, "type": snapshot.Type, "status": snapshot.Status,
			"detail": snapshot.StatusDetail, "bucket": snapshot.Bucket,
			"key": snapshot.Key, "createdAt": snapshot.CreatedAt,
			"bytes": fmt.Sprintf("%d/%d", snapshot.BytesCompleted, snapshot.TotalBytes),
		})
	}
	writeDebugJSON(w, map[string]any{"items": items})
}

func writeDebugJSON(w http.ResponseWriter, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	encoded, err := json.MarshalIndent(payload, "", "  ")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	_, _ = w.Write(encoded)
}
