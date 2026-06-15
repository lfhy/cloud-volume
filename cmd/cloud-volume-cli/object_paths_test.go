package main

import "testing"

func TestResolveVisiblePath(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name    string
		baseDir string
		input   string
		want    string
	}{
		{name: "empty keeps current dir", baseDir: "docs/api", input: "", want: "docs/api"},
		{name: "relative appends to current dir", baseDir: "docs", input: "api/v1", want: "docs/api/v1"},
		{name: "parent segments collapse", baseDir: "docs/api", input: "../guide", want: "docs/guide"},
		{name: "absolute path resets to root", baseDir: "docs/api", input: "/images/logo.png", want: "images/logo.png"},
		{name: "walk above root clamps at root", baseDir: "docs", input: "../../top", want: "top"},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := resolveVisiblePath(tc.baseDir, tc.input); got != tc.want {
				t.Fatalf("resolveVisiblePath(%q, %q) = %q, want %q", tc.baseDir, tc.input, got, tc.want)
			}
		})
	}
}

func TestRelativeListedPath(t *testing.T) {
	t.Parallel()

	if got := relativeListedPath("docs", "docs/api/spec.yaml", false); got != "api/spec.yaml" {
		t.Fatalf("relativeListedPath file = %q, want %q", got, "api/spec.yaml")
	}
	if got := relativeListedPath("docs", "docs/api/", true); got != "api/" {
		t.Fatalf("relativeListedPath dir = %q, want %q", got, "api/")
	}
}

func TestRelativeDownloadPath(t *testing.T) {
	t.Parallel()

	if got := relativeDownloadPath("docs/archive", "docs/archive/2026/report.csv"); got != "2026/report.csv" {
		t.Fatalf("relativeDownloadPath nested file = %q, want %q", got, "2026/report.csv")
	}
	if got := relativeDownloadPath("", "top-level.txt"); got != "top-level.txt" {
		t.Fatalf("relativeDownloadPath root file = %q, want %q", got, "top-level.txt")
	}
}
