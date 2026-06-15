package main

import (
	"io"
	"log"
	"os"
	"path/filepath"
	"sync"

	storageconfig "remote-storage/go/config"
)

var configureBridgeLoggerOnce sync.Once

func init() {
	configureBridgeLogger()
}

// configureBridgeLogger mirrors bridge diagnostics to a stable runtime log file.
func configureBridgeLogger() {
	configureBridgeLoggerOnce.Do(func() {
		log.SetFlags(log.LstdFlags | log.Lmicroseconds | log.Lshortfile)

		logPath, err := storageconfig.BridgeLogPath()
		if err != nil {
			log.Printf("[bridge/log] resolve log path: %v", err)
			return
		}
		if err := os.MkdirAll(filepath.Dir(logPath), 0o755); err != nil {
			log.Printf("[bridge/log] create log dir %q: %v", filepath.Dir(logPath), err)
			return
		}

		file, err := os.OpenFile(logPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
		if err != nil {
			log.Printf("[bridge/log] open log file %q: %v", logPath, err)
			return
		}

		log.SetOutput(io.MultiWriter(os.Stderr, file))
		log.Printf("[bridge/log] writing Go bridge logs to %s", logPath)
	})
}
