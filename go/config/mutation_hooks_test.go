package config

import (
	"runtime"
	"sync/atomic"
	"testing"
)

func TestSaveProfileNotifiesMutationHookAfterSuccess(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	if runtime.GOOS == "windows" {
		t.Setenv("USERPROFILE", home)
	}

	var calls atomic.Int32
	SetProfileMutationHook(func() { calls.Add(1) })
	defer SetProfileMutationHook(nil)

	if err := SaveProfile("hooked", validTestConfig()); err != nil {
		t.Fatalf("save profile: %v", err)
	}
	if got := calls.Load(); got != 1 {
		t.Fatalf("mutation hook calls = %d, want 1", got)
	}
}

func TestSaveProfileDoesNotNotifyMutationHookOnFailure(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	if runtime.GOOS == "windows" {
		t.Setenv("USERPROFILE", home)
	}

	var calls atomic.Int32
	SetProfileMutationHook(func() { calls.Add(1) })
	defer SetProfileMutationHook(nil)

	if err := SaveProfile("", validTestConfig()); err == nil {
		t.Fatal("save profile with empty name unexpectedly succeeded")
	}
	if got := calls.Load(); got != 0 {
		t.Fatalf("mutation hook calls = %d, want 0", got)
	}
}
