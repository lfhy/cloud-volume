// The init command collects and optionally validates the persisted S3 config.
package main

import (
	"fmt"
	"strings"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

func runInitCommand(args []string) error {
	flags := newFlagSet("init")
	configPath := flags.String("config", "", "config file path")
	skipValidate := flags.Bool("skip-validate", false, "skip endpoint and credential validation")
	if err := flags.Parse(args); err != nil {
		return err
	}

	store, resolvedPath, err := openConfigStore(*configPath)
	if err != nil {
		return err
	}
	current, err := store.Load()
	if err != nil {
		return err
	}

	ui := newPromptUI()
	fmt.Fprintf(ui.out, "配置文件: %s\n", resolvedPath)
	fmt.Fprintln(ui.out, "请输入 S3 兼容存储配置。直接回车会保留当前值。")

	cfg := current
	if !cfg.IsConfigured() &&
		strings.TrimSpace(cfg.Endpoint) == "" &&
		strings.TrimSpace(cfg.AccessKeyID) == "" &&
		strings.TrimSpace(cfg.WebDAVUsername) == "" {
		cfg = storageconfig.DefaultConfig()
	}

	if cfg.Endpoint, err = ui.askString("Endpoint", cfg.Endpoint, true); err != nil {
		return err
	}
	if cfg.Region, err = ui.askString("Region", cfg.Region, false); err != nil {
		return err
	}
	if cfg.AccessKeyID, err = ui.askString("Access Key ID", cfg.AccessKeyID, true); err != nil {
		return err
	}
	if cfg.SecretAccessKey, err = ui.askSecret("Secret Access Key", cfg.SecretAccessKey); err != nil {
		return err
	}
	if cfg.UsePathStyle, err = ui.askBool("启用 path-style URL", cfg.UsePathStyle); err != nil {
		return err
	}

	cfg = cfg.Normalized()
	if !*skipValidate {
		fmt.Fprintln(ui.out, "正在拉取 bucket 列表...")
		buckets, err := s3ops.ListBuckets(cfg)
		if err != nil {
			return fmt.Errorf("拉取 bucket 列表失败: %w", err)
		}
		if len(buckets) == 0 {
			cfg.Bucket = ""
			fmt.Fprintln(ui.out, "当前账号下没有可用 bucket。")
		} else {
			options := make([]string, 0, len(buckets))
			for _, bucket := range buckets {
				if strings.TrimSpace(bucket.Name) == "" {
					continue
				}
				options = append(options, strings.TrimSpace(bucket.Name))
			}
			if len(options) == 0 {
				cfg.Bucket = ""
				fmt.Fprintln(ui.out, "当前账号下没有可用 bucket。")
			} else {
				selected, err := ui.askOptionalChoice("默认 Bucket", options, cfg.Bucket)
				if err != nil {
					return err
				}
				cfg.Bucket = strings.TrimSpace(selected)
			}
		}
		if err := s3ops.CheckAccess(cfg); err != nil {
			return fmt.Errorf("校验配置失败: %w", err)
		}
	}
	if err := store.Save(cfg); err != nil {
		return err
	}

	fmt.Fprintf(ui.out, "已保存配置到 %s\n", resolvedPath)
	if strings.TrimSpace(cfg.Bucket) != "" {
		fmt.Fprintf(ui.out, "默认 Bucket: %s\n", cfg.Bucket)
	}
	if activeShell != nil && strings.TrimSpace(cfg.Bucket) != "" {
		activeShell.bucketOverride = strings.TrimSpace(cfg.Bucket)
	}
	return nil
}
