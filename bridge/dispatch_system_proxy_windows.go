//go:build windows

// Windows-specific system proxy reader: parses the per-user Internet Settings
// registry key written by Settings -> Network & Internet -> Proxy. This covers
// the common manual-proxy case (ProxyEnable=1, ProxyServer="host:port"). PAC
// auto-config URLs are reported as unavailable because the Dart HTTP stack
// cannot evaluate proxy scripts.
package main

import (
	"golang.org/x/sys/windows/registry"
	"strings"
)

func readSystemProxy() systemProxyResult {
	k, err := registry.OpenKey(registry.CURRENT_USER,
		`Software\Microsoft\Windows\CurrentVersion\Internet Settings`,
		registry.QUERY_VALUE)
	if err != nil {
		return systemProxyResult{}
	}
	defer k.Close()
	enable, _, err := k.GetIntegerValue("ProxyEnable")
	if err != nil || enable == 0 {
		return systemProxyResult{}
	}
	server, _, err := k.GetStringValue("ProxyServer")
	if err != nil {
		return systemProxyResult{}
	}
	server = strings.TrimSpace(server)
	if server == "" {
		return systemProxyResult{}
	}
	// ProxyServer may contain multiple per-protocol entries separated by ';',
	// e.g. "http=127.0.0.1:7890;https=127.0.0.1:7890". Prefer https/all when
	// present, otherwise take the first entry, then strip a "scheme=" prefix.
	host, port, ptype := parseWindowsProxyServer(server)
	if host == "" {
		return systemProxyResult{}
	}
	return systemProxyResult{
		Available: true,
		Type:      ptype,
		Host:      host,
		Port:      port,
	}
}

// parseWindowsProxyServer extracts host/port/type from a Windows ProxyServer value.
func parseWindowsProxyServer(server string) (host, port, ptype string) {
	entries := strings.Split(server, ";")
	pick := ""
	for _, entry := range entries {
		entry = strings.TrimSpace(entry)
		if entry == "" {
			continue
		}
		if strings.HasPrefix(strings.ToLower(entry), "socks=") {
			pick = entry
			ptype = "socks5"
			break
		}
		if pick == "" {
			pick = entry
		}
		if strings.HasPrefix(strings.ToLower(entry), "https=") || !strings.Contains(entry, "=") {
			pick = entry
		}
	}
	if pick == "" {
		return "", "", ""
	}
	if idx := strings.Index(pick, "="); idx >= 0 {
		pick = pick[idx+1:]
	}
	parts := strings.SplitN(pick, ":", 2)
	if len(parts) == 1 {
		return parts[0], "", "http"
	}
	if parts[0] == "" || parts[1] == "" {
		return "", "", ""
	}
	if ptype == "" {
		ptype = "http"
	}
	return parts[0], parts[1], ptype
}
