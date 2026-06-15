// CLI logging mirrors runtime diagnostics into a stable log file for mount debugging.
package main

import (
	"io"
	"log"
	"os"
	"path/filepath"
	"sync"

	storageconfig "remote-storage/go/config"
)

var configureCLILoggerOnce sync.Once

func init() {
	configureCLILogger()
}

func configureCLILogger() {
	configureCLILoggerOnce.Do(func() {
		log.SetFlags(log.LstdFlags | log.Lmicroseconds | log.Lshortfile)

		logPath, err := cliLogPath()
		if err != nil {
			log.Printf("[cli/log] resolve log path: %v", err)
			return
		}
		if err := os.MkdirAll(filepath.Dir(logPath), 0o755); err != nil {
			log.Printf("[cli/log] create log dir %q: %v", filepath.Dir(logPath), err)
			return
		}

		file, err := os.OpenFile(logPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
		if err != nil {
			log.Printf("[cli/log] open log file %q: %v", logPath, err)
			return
		}

		log.SetOutput(io.MultiWriter(os.Stderr, file))
		log.Printf("[cli/log] writing CLI logs to %s", logPath)
	})
}

func cliLogPath() (string, error) {
	logsDir, err := storageconfig.LogsRuntimeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(logsDir, "cli.log"), nil
}
