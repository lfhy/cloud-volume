// Config tests pin trash-directory normalization and reserved alias behavior.
package config

import (
	"path/filepath"
	"testing"
)

func TestTrashDirectoryAliases(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name  string
		input string
		want  []string
	}{
		{name: "empty defaults to lowercase plus Finder alias", input: "", want: []string{".trash", ".Trash"}},
		{name: "lowercase keeps Finder alias", input: ".trash", want: []string{".trash", ".Trash"}},
		{name: "uppercase keeps app alias", input: ".Trash", want: []string{".Trash", ".trash"}},
		{name: "custom name stays single", input: ".recycle", want: []string{".recycle"}},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got := TrashDirectoryAliases(tc.input)
			if len(got) != len(tc.want) {
				t.Fatalf("len = %d, want %d (%v)", len(got), len(tc.want), got)
			}
			for index := range tc.want {
				if got[index] != tc.want[index] {
					t.Fatalf("aliases[%d] = %q, want %q (%v)", index, got[index], tc.want[index], got)
				}
			}
		})
	}
}

func TestNormalizeWindowsMountMode(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name  string
		input string
		want  string
	}{
		{
			name:  "empty defaults to cached cloud files",
			input: "",
			want:  WindowsMountModeCloudFilesCached,
		},
		{
			name:  "direct cloud files stays enabled",
			input: WindowsMountModeCloudFilesDirect,
			want:  WindowsMountModeCloudFilesDirect,
		},
		{
			name:  "webdav stays enabled",
			input: WindowsMountModeWebDAV,
			want:  WindowsMountModeWebDAV,
		},
		{
			name:  "unknown falls back to cached cloud files",
			input: "unknown",
			want:  WindowsMountModeCloudFilesCached,
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := normalizeWindowsMountMode(tc.input); got != tc.want {
				t.Fatalf("normalizeWindowsMountMode(%q) = %q, want %q", tc.input, got, tc.want)
			}
		})
	}
}

func TestResolveCacheDirUsesConfiguredPath(t *testing.T) {
	t.Parallel()

	rawPath := filepath.Join(t.TempDir(), "cache", "nested", "..")
	got, err := ResolveCacheDir(RemoteStorageConfig{CacheDirectory: " " + rawPath + " "})
	if err != nil {
		t.Fatalf("ResolveCacheDir returned error: %v", err)
	}
	if got != filepath.Clean(rawPath) {
		t.Fatalf("ResolveCacheDir = %q, want %q", got, filepath.Clean(rawPath))
	}
}

func TestDefaultWindowsThisPcEntryDisabled(t *testing.T) {
	t.Parallel()

	if DefaultConfig().WindowsThisPcEntryEnabled {
		t.Fatal("expected Windows This PC entry to be disabled by default")
	}
}

func TestNormalizeWindowsWritebackConcurrency(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name  string
		input int
		want  int
	}{
		{name: "zero falls back to default", input: 0, want: 4},
		{name: "negative falls back to default", input: -1, want: 4},
		{name: "small positive stays unchanged", input: 2, want: 2},
		{name: "large values are capped", input: 99, want: 32},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := normalizeWindowsWritebackConcurrency(tc.input); got != tc.want {
				t.Fatalf(
					"normalizeWindowsWritebackConcurrency(%d) = %d, want %d",
					tc.input,
					got,
					tc.want,
				)
			}
		})
	}
}

func TestNormalizeWritebackQuietSeconds(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name  string
		input int
		want  int
	}{
		{name: "zero falls back to ten seconds", input: 0, want: 10},
		{name: "negative falls back to ten seconds", input: -1, want: 10},
		{name: "small positive stays unchanged", input: 3, want: 3},
		{name: "large values are capped", input: 999, want: 300},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := normalizeWritebackQuietSeconds(tc.input); got != tc.want {
				t.Fatalf(
					"normalizeWritebackQuietSeconds(%d) = %d, want %d",
					tc.input,
					got,
					tc.want,
				)
			}
		})
	}
}

func TestWithDefaultWebDAVCredentialsFallsBackToAccessKeys(t *testing.T) {
	t.Parallel()

	config := RemoteStorageConfig{
		Endpoint:           "https://example.invalid",
		AccessKeyID:        "ak-test",
		SecretAccessKey:    "sk-test",
		HasSecretAccessKey: true,
	}

	got := config.WithDefaultWebDAVCredentials()
	if got.WebDAVUsername != "ak-test" {
		t.Fatalf("WebDAVUsername = %q, want %q", got.WebDAVUsername, "ak-test")
	}
	if got.WebDAVPassword != "sk-test" {
		t.Fatalf("WebDAVPassword = %q, want %q", got.WebDAVPassword, "sk-test")
	}
	if !got.HasWebDAVPassword {
		t.Fatal("expected HasWebDAVPassword to be true after defaulting")
	}
}

func TestWithDefaultWebDAVCredentialsKeepsExplicitValues(t *testing.T) {
	t.Parallel()

	config := RemoteStorageConfig{
		AccessKeyID:       "ak-test",
		SecretAccessKey:   "sk-test",
		WebDAVUsername:    "custom-user",
		WebDAVPassword:    "custom-pass",
		HasWebDAVPassword: true,
	}

	got := config.WithDefaultWebDAVCredentials()
	if got.WebDAVUsername != "custom-user" {
		t.Fatalf("WebDAVUsername = %q, want %q", got.WebDAVUsername, "custom-user")
	}
	if got.WebDAVPassword != "custom-pass" {
		t.Fatalf("WebDAVPassword = %q, want %q", got.WebDAVPassword, "custom-pass")
	}
}

func TestMappedBucketNameDefaultsToDisplayName(t *testing.T) {
	t.Parallel()

	config := RemoteStorageConfig{DisplayName: "  Second DAV  "}
	if got := config.Normalized().MappedBucketName; got != "Second DAV" {
		t.Fatalf("MappedBucketName = %q, want %q", got, "Second DAV")
	}
}

func TestMappedBucketNameKeepsExplicitValue(t *testing.T) {
	t.Parallel()

	config := RemoteStorageConfig{
		DisplayName:      "Account Name",
		MappedBucketName: "  My Bucket  ",
	}
	if got := config.Normalized().MappedBucketName; got != "My Bucket" {
		t.Fatalf("MappedBucketName = %q, want %q", got, "My Bucket")
	}
}
