//go:build !windows

// Non-Windows hosts fall back to environment-variable detection; system proxies
// configured via desktop settings are not exposed through a portable registry API.
package main

func readSystemProxy() systemProxyResult {
	return systemProxyResult{}
}
