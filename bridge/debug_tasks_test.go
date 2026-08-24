// Debug listener tests keep the diagnostics surface localhost-only.
package main

import "testing"

func TestIsLoopbackDebugAddr(t *testing.T) {
	for _, addr := range []string{"127.0.0.1:8765", "[::1]:8765"} {
		if !isLoopbackDebugAddr(addr) {
			t.Fatalf("loopback addr %q was rejected", addr)
		}
	}
	for _, addr := range []string{"0.0.0.0:8765", "192.168.1.2:8765", "localhost:8765", "127.0.0.1"} {
		if isLoopbackDebugAddr(addr) {
			t.Fatalf("non-loopback addr %q was accepted", addr)
		}
	}
}
