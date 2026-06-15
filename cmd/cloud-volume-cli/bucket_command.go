// Bucket commands expose list/select flows that are shared between shell and direct CLI usage.
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	s3ops "remote-storage/go/s3"
)

func runBucketCommand(args []string) error {
	flags := newFlagSet("bucket")
	configPath := flags.String("config", "", "config file path")
	jsonOutput := flags.Bool("json", false, "print JSON output")
	if err := flags.Parse(args); err != nil {
		return err
	}
	remaining := flags.Args()

	loaded, err := loadConfiguredConfig(*configPath)
	if err != nil {
		return err
	}

	switch len(remaining) {
	case 0:
		selected, err := chooseBucketInteractively(loaded)
		if err != nil {
			return err
		}
		applySelectedBucket(selected)
		fmt.Fprintln(stdoutWriter(), selected)
		return nil
	case 1:
		subject := strings.TrimSpace(remaining[0])
		switch strings.ToLower(subject) {
		case "list", "ls":
			return printBucketList(loaded, *jsonOutput)
		default:
			applySelectedBucket(subject)
			fmt.Fprintln(stdoutWriter(), subject)
			return nil
		}
	default:
		return errors.New("bucket 用法: bucket | bucket list | bucket <name>")
	}
}

func printBucketList(loaded loadedConfig, jsonOutput bool) error {
	buckets, err := s3ops.ListBuckets(loaded.cfg)
	if err != nil {
		return err
	}
	names := make([]string, 0, len(buckets))
	for _, bucket := range buckets {
		if strings.TrimSpace(bucket.Name) == "" {
			continue
		}
		names = append(names, strings.TrimSpace(bucket.Name))
	}
	if jsonOutput {
		encoder := json.NewEncoder(stdoutWriter())
		encoder.SetIndent("", "  ")
		return encoder.Encode(names)
	}
	for _, name := range names {
		fmt.Fprintln(stdoutWriter(), name)
	}
	return nil
}

func applySelectedBucket(bucket string) {
	trimmed := strings.TrimSpace(bucket)
	if activeShell != nil {
		activeShell.bucketOverride = trimmed
		activeShell.currentDir = ""
	}
}
