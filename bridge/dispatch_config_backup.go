// Configuration backup bridge handlers keep backup traffic out of profile management.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	storageconfig "remote-storage/go/config"
	configbackup "remote-storage/go/configbackup"
	bucketmount "remote-storage/go/mount"
)

var automaticConfigBackup struct {
	sync.Mutex
	pending   bool
	uploading bool
	rerun     bool
}

var (
	automaticConfigBackupDelay = 2 * time.Second
	backupConfigSnapshot       = configbackup.BackupNow
)

func init() {
	// Profile writes from storage, including background OAuth refreshes, must
	// enter the same coalesced automatic-backup queue as bridge mutations.
	storageconfig.SetProfileMutationHook(queueAutomaticConfigBackup)
}

type configBackupSettingsArgs struct {
	Settings storageconfig.ConfigBackupSettings `json:"settings"`
}

type configBackupRestoreArgs struct {
	Key string `json:"key"`
}

type configBackupDeleteArgs struct {
	Key string `json:"key"`
}

// configBackupTargetArgs carries an inline backup target for the first-run
// restore flow, where no local backup settings exist yet.
type configBackupTargetArgs struct {
	Target storageconfig.ConfigBackupTarget `json:"target"`
}

// configBackupRestoreTargetArgs carries target + key for inline-target restore.
// The optional PasswordOverride lets the caller supply a decrypt password that
// differs from the target's stored BackupPassword (e.g. first-run restore on a
// new machine where no local password is configured).
type configBackupRestoreTargetArgs struct {
	Target           storageconfig.ConfigBackupTarget `json:"target"`
	Key              string                           `json:"key"`
	PasswordOverride string                           `json:"passwordOverride,omitempty"`
}

func loadConfigBackupSettings() (any, error) {
	return storageconfig.LoadConfigBackupSettings()
}

func saveConfigBackupSettings(args json.RawMessage) (any, error) {
	var input configBackupSettingsArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageconfig.SaveConfigBackupSettings(input.Settings); err != nil {
		return nil, err
	}
	return storageconfig.LoadConfigBackupSettings()
}

func backupConfigNow() (any, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	return configbackup.BackupNow(ctx)
}

func listConfigBackups() (any, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	return configbackup.List(ctx)
}

func restoreConfigBackup(args json.RawMessage) (any, error) {
	var input configBackupRestoreArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	if err := bucketmount.CleanupMounts(); err != nil {
		return nil, fmt.Errorf("还原前卸载现有挂载失败：%w", err)
	}
	if err := configbackup.Restore(ctx, input.Key); err != nil {
		return nil, err
	}
	return loadBootstrapState()
}

func deleteConfigBackup(args json.RawMessage) (any, error) {
	var input configBackupDeleteArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	if err := configbackup.Delete(ctx, input.Key); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

// listConfigBackupsWithTarget lists snapshots using an inline target, for the
// first-run restore flow where no local backup settings exist yet.
func listConfigBackupsWithTarget(args json.RawMessage) (any, error) {
	var input configBackupTargetArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	return configbackup.ListWithTarget(ctx, input.Target)
}

// restoreConfigBackupWithTarget restores a snapshot using an inline target.
// After a successful restore the inline target is persisted as the new backup
// settings so future automatic backups go to the same location.
func restoreConfigBackupWithTarget(args json.RawMessage) (any, error) {
	var input configBackupRestoreTargetArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	if err := bucketmount.CleanupMounts(); err != nil {
		return nil, fmt.Errorf("还原前卸载现有挂载失败：%w", err)
	}
	// Apply password override when the caller provides one (first-run flow).
	restoreTarget := input.Target
	if password := strings.TrimSpace(input.PasswordOverride); password != "" {
		restoreTarget = restoreTarget.CopyWithPassword(password)
	}
	if err := configbackup.RestoreWithTarget(ctx, restoreTarget, input.Key); err != nil {
		return nil, err
	}
	// Persist the inline target (with the password) as backup settings so
	// automatic backups continue to the same storage. Enabled defaults to
	// true so the user does not need to reconfigure after restore.
	if err := storageconfig.SaveConfigBackupSettings(storageconfig.ConfigBackupSettings{
		Enabled:           true,
		EncryptionEnabled: restoreTarget.BackupPassword != "",
		Target:            restoreTarget,
	}); err != nil {
		// Non-fatal: restore itself succeeded; settings persistence is best-effort.
		log.Printf("[config-backup] failed to persist restore target: %v", err)
	}
	return loadBootstrapState()
}

// verifyBackupPassword checks that the given target + password can decrypt a
// snapshot without applying it. Used by the UI to decide whether to prompt.
func verifyBackupPassword(args json.RawMessage) (any, error) {
	var input configBackupRestoreTargetArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	target := input.Target
	if password := strings.TrimSpace(input.PasswordOverride); password != "" {
		target = target.CopyWithPassword(password)
	}
	if err := configbackup.VerifyPassword(ctx, target, input.Key); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

// queueAutomaticConfigBackup never makes saving an account depend on remote availability.
func queueAutomaticConfigBackup() {
	automaticConfigBackup.Lock()
	if automaticConfigBackup.pending {
		if automaticConfigBackup.uploading {
			automaticConfigBackup.rerun = true
		}
		automaticConfigBackup.Unlock()
		return
	}
	automaticConfigBackup.pending = true
	automaticConfigBackup.Unlock()
	go func() {
		defer func() {
			automaticConfigBackup.Lock()
			automaticConfigBackup.uploading = false
			automaticConfigBackup.pending = false
			rerun := automaticConfigBackup.rerun
			automaticConfigBackup.rerun = false
			automaticConfigBackup.Unlock()
			if rerun {
				// A token refresh can persist a profile while the upload is in
				// flight; queue one follow-up snapshot so it contains that write.
				queueAutomaticConfigBackup()
			}
		}()
		// Coalesce the multiple writes made by a single settings edit.
		time.Sleep(automaticConfigBackupDelay)
		settings, err := storageconfig.LoadConfigBackupSettings()
		if err != nil || !settings.Enabled {
			return
		}
		automaticConfigBackup.Lock()
		automaticConfigBackup.uploading = true
		automaticConfigBackup.Unlock()
		ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
		defer cancel()
		if _, err := backupConfigSnapshot(ctx); err != nil {
			log.Printf("[config-backup] automatic backup failed: %v", err)
		}
	}()
}
