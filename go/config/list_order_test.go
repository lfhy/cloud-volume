// Tests for persisted account/bucket list ordering in config.db meta.
package config

import "testing"

func TestReorderProfilesPersistsListOrder(t *testing.T) {
	home := t.TempDir()
	setTestHome(t, home)

	if err := SaveProfile("alpha", validTestConfig()); err != nil {
		t.Fatalf("SaveProfile alpha: %v", err)
	}
	if err := SaveProfile("beta", validTestConfig()); err != nil {
		t.Fatalf("SaveProfile beta: %v", err)
	}
	if err := SaveProfile("gamma", validTestConfig()); err != nil {
		t.Fatalf("SaveProfile gamma: %v", err)
	}
	if err := SetActiveProfile("alpha"); err != nil {
		t.Fatalf("SetActiveProfile: %v", err)
	}

	// Without a custom order, active still comes first.
	profiles, err := ListProfiles()
	if err != nil {
		t.Fatalf("ListProfiles: %v", err)
	}
	if len(profiles) != 3 || profiles[0].Name != "alpha" {
		t.Fatalf("expected active alpha first by default, got %#v", profiles)
	}

	if err := ReorderProfiles([]string{"gamma", "alpha", "beta"}); err != nil {
		t.Fatalf("ReorderProfiles: %v", err)
	}
	profiles, err = ListProfiles()
	if err != nil {
		t.Fatalf("ListProfiles after reorder: %v", err)
	}
	got := make([]string, 0, len(profiles))
	for _, profile := range profiles {
		got = append(got, profile.Name)
	}
	want := []string{"gamma", "alpha", "beta"}
	if len(got) != len(want) {
		t.Fatalf("unexpected profile count: got %v want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("unexpected order at %d: got %v want %v", i, got, want)
		}
	}

	// Newly saved profiles append to the custom order.
	if err := SaveProfile("delta", validTestConfig()); err != nil {
		t.Fatalf("SaveProfile delta: %v", err)
	}
	profiles, _ = ListProfiles()
	if profiles[len(profiles)-1].Name != "delta" {
		t.Fatalf("expected delta appended, got %#v", profiles)
	}

	// Deleting a profile removes it from the order.
	if err := DeleteProfile("alpha"); err != nil {
		t.Fatalf("DeleteProfile: %v", err)
	}
	profiles, _ = ListProfiles()
	for _, profile := range profiles {
		if profile.Name == "alpha" {
			t.Fatalf("alpha still listed after delete: %#v", profiles)
		}
	}
}

func TestReorderBucketsPersistsIds(t *testing.T) {
	home := t.TempDir()
	setTestHome(t, home)

	ids := []string{"acct::bucket-b", "acct::bucket-a", "other::root"}
	if err := ReorderBuckets(ids); err != nil {
		t.Fatalf("ReorderBuckets: %v", err)
	}
	got, err := ListBucketOrder()
	if err != nil {
		t.Fatalf("ListBucketOrder: %v", err)
	}
	if len(got) != len(ids) {
		t.Fatalf("unexpected ids: got %v want %v", got, ids)
	}
	for i := range ids {
		if got[i] != ids[i] {
			t.Fatalf("unexpected id at %d: got %v want %v", i, got, ids)
		}
	}

	// Reset clears custom orders.
	if err := SaveProfile("acct", validTestConfig()); err != nil {
		t.Fatalf("SaveProfile: %v", err)
	}
	if err := ResetAllProfiles(); err != nil {
		t.Fatalf("ResetAllProfiles: %v", err)
	}
	got, err = ListBucketOrder()
	if err != nil {
		t.Fatalf("ListBucketOrder after reset: %v", err)
	}
	if len(got) != 0 {
		t.Fatalf("expected empty bucket order after reset, got %v", got)
	}
}
