// Shared web command helpers keep CLI full builds aligned with cmd/web behavior.
package main

import (
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"remote-storage/go/webapi"
)

func serveWeb(options webapi.Options, listenAddr string) error {
	server := webapi.NewServer(options)
	httpServer := &http.Server{
		Addr:              listenAddr,
		Handler:           server.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}
	errorCh := make(chan error, 1)
	go func() {
		log.Printf("[web] listening on %s", listenAddr)
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			errorCh <- err
		}
		close(errorCh)
	}()

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGINT, syscall.SIGTERM)
	defer signal.Stop(signals)

	select {
	case err, ok := <-errorCh:
		if ok && err != nil {
			_ = server.Close()
			return err
		}
		return nil
	case <-signals:
	}

	if err := httpServer.Close(); err != nil {
		log.Printf("[web] close server: %v", err)
	}
	if err := server.Close(); err != nil {
		log.Printf("[web] cleanup: %v", err)
	}
	return nil
}
