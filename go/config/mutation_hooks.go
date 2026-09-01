// Profile mutation hooks let integration layers observe successful config writes without package cycles.
package config

import "sync"

var profileMutationHook struct {
	sync.RWMutex
	fn func()
}

// SetProfileMutationHook installs the process-wide observer invoked after a
// profile has been persisted successfully. Passing nil removes the observer.
func SetProfileMutationHook(fn func()) {
	profileMutationHook.Lock()
	profileMutationHook.fn = fn
	profileMutationHook.Unlock()
}

func notifyProfileMutation() {
	profileMutationHook.RLock()
	fn := profileMutationHook.fn
	profileMutationHook.RUnlock()
	if fn != nil {
		fn()
	}
}
