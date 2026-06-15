// List commands expose the existing paged S3 listing as a shell-friendly table or JSON.
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"text/tabwriter"

	s3ops "remote-storage/go/s3"
)

func runListCommand(args []string) error {
	flags := newFlagSet("ls")
	configPath := flags.String("config", "", "config file path")
	bucketName := flags.String("bucket", "", "bucket name")
	jsonOutput := flags.Bool("json", false, "print JSON output")
	if err := flags.Parse(args); err != nil {
		return err
	}
	remaining := flags.Args()
	if len(remaining) > 1 {
		return errors.New("ls/list 只接受一个可选 prefix 位置参数")
	}

	prefix := currentShellDir()
	if len(remaining) == 1 {
		prefix = resolveVisiblePath(currentShellDir(), remaining[0])
	}
	target, err := resolveObjectTarget(*configPath, *bucketName, prefix)
	if err != nil {
		return err
	}
	visibleItems, err := listVisibleObjects(target.config, target.bucket, target.visibleKey)
	if err != nil {
		return err
	}

	if *jsonOutput {
		encoder := json.NewEncoder(stdoutWriter())
		encoder.SetIndent("", "  ")
		return encoder.Encode(visibleItems)
	}
	return printListTable(visibleItems)
}

func printListTable(items []s3ops.ObjectInfo) error {
	writer := tabwriter.NewWriter(stdoutWriter(), 0, 4, 2, ' ', 0)
	if _, err := fmt.Fprintln(writer, "TYPE\tSIZE\tUPDATED\tPATH"); err != nil {
		return err
	}
	for _, item := range items {
		size := "-"
		if !item.IsDir {
			size = fmt.Sprintf("%d", item.Size)
		}
		itemType := "FILE"
		if item.IsDir {
			itemType = "DIR"
		}
		if _, err := fmt.Fprintf(
			writer,
			"%s\t%s\t%s\t%s\n",
			itemType,
			size,
			strings.TrimSpace(item.LastModified),
			item.Key,
		); err != nil {
			return err
		}
	}
	return writer.Flush()
}
