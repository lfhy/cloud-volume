// Shared config-db tests cover Android FFI concurrency and mobile-root swaps.
package config

import (
	"fmt"
	"sync"
	"testing"
	"time"

	bolt "go.etcd.io/bbolt"
)

func TestConfigDBReusesOneHandleAndWaitsForRootSwitch(t *testing.T) {
	restoreAppDataRoot(t)
	rootOne := t.TempDir()
	rootTwo := t.TempDir()
	if err := SetAppDataRoot(rootOne); err != nil {
		t.Fatalf("SetAppDataRoot(%q): %v", rootOne, err)
	}

	first, releaseFirst, err := acquireConfigDB()
	if err != nil {
		t.Fatalf("first config-db lease: %v", err)
	}
	defer releaseFirst()
	second, releaseSecond, err := acquireConfigDB()
	if err != nil {
		t.Fatalf("second config-db lease: %v", err)
	}
	defer releaseSecond()
	if first != second {
		t.Fatal("consecutive config-db leases returned different handles")
	}
	releaseSecond()

	switched := make(chan error, 1)
	go func() {
		switched <- SetAppDataRoot(rootTwo)
	}()
	waitForConfigDBRootSwitch(t)
	if err := first.View(func(tx *bolt.Tx) error {
		if tx.Bucket(metaBucketKey) == nil {
			return fmt.Errorf("meta bucket missing")
		}
		return nil
	}); err != nil {
		t.Fatalf("active lease lost its usable config-db handle: %v", err)
	}
	select {
	case err := <-switched:
		t.Fatalf("root switch completed before active lease released: %v", err)
	default:
	}

	releaseFirst()
	if err := <-switched; err != nil {
		t.Fatalf("SetAppDataRoot(%q): %v", rootTwo, err)
	}
	third, releaseThird, err := acquireConfigDB()
	if err != nil {
		t.Fatalf("config-db lease after root switch: %v", err)
	}
	defer releaseThird()
	if third == first {
		t.Fatal("root switch reused the closed config-db handle")
	}
}

func TestSetAppDataRootSamePathDoesNotInterruptActiveConfigLease(t *testing.T) {
	restoreAppDataRoot(t)
	root := t.TempDir()
	if err := SetAppDataRoot(root); err != nil {
		t.Fatalf("SetAppDataRoot(%q): %v", root, err)
	}
	_, release, err := acquireConfigDB()
	if err != nil {
		t.Fatalf("config-db lease: %v", err)
	}
	defer release()

	completed := make(chan error, 1)
	go func() {
		completed <- SetAppDataRoot(root)
	}()
	select {
	case err := <-completed:
		if err != nil {
			t.Fatalf("repeat SetAppDataRoot(%q): %v", root, err)
		}
	case <-time.After(time.Second):
		t.Fatal("repeat SetAppDataRoot waited for an active lease")
	}
}

func waitForConfigDBRootSwitch(t *testing.T) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		sharedConfigDB.mu.Lock()
		switching := sharedConfigDB.switching
		sharedConfigDB.mu.Unlock()
		if switching {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("timed out waiting for config-db root switch")
}

func TestRestoreConfigBackupRepeatedlyKeepsBboltConsistent(t *testing.T) {
	setTestHome(t, t.TempDir())
	alpha := validTestConfig()
	alpha.Endpoint = "https://alpha.example"
	if err := SaveProfile("alpha", alpha); err != nil {
		t.Fatal(err)
	}
	if err := SetActiveProfile("alpha"); err != nil {
		t.Fatal(err)
	}
	if err := SaveConfigBackupSettings(ConfigBackupSettings{
		Enabled: true,
		Target:  ConfigBackupTarget{ProfileName: "alpha", Bucket: "backup"},
	}); err != nil {
		t.Fatal(err)
	}
	archive, err := ExportConfigBackup()
	if err != nil {
		t.Fatal(err)
	}

	for i := 0; i < 64; i++ {
		if err := SaveProfile(fmt.Sprintf("temporary-%d", i), validTestConfig()); err != nil {
			t.Fatal(err)
		}
		if err := RestoreConfigBackup(archive); err != nil {
			t.Fatalf("restore %d: %v", i, err)
		}
	}
	assertConfigDBConsistent(t)
}

func TestRestoreConfigBackupSharesOneHandleWithConcurrentPollReads(t *testing.T) {
	setTestHome(t, t.TempDir())
	alpha := validTestConfig()
	alpha.Endpoint = "https://alpha.example"
	if err := SaveProfile("alpha", alpha); err != nil {
		t.Fatal(err)
	}
	if err := SetActiveProfile("alpha"); err != nil {
		t.Fatal(err)
	}
	if err := SaveConfigBackupSettings(ConfigBackupSettings{
		Enabled: true,
		Target:  ConfigBackupTarget{ProfileName: "alpha", Bucket: "backup"},
	}); err != nil {
		t.Fatal(err)
	}
	archive, err := ExportConfigBackup()
	if err != nil {
		t.Fatal(err)
	}

	const readers = 4
	errs := make(chan error, readers+1)
	start := make(chan struct{})
	var workers sync.WaitGroup
	workers.Add(1)
	go func() {
		defer workers.Done()
		<-start
		for i := 0; i < 24; i++ {
			if err := RestoreConfigBackup(archive); err != nil {
				errs <- fmt.Errorf("restore %d: %w", i, err)
				return
			}
		}
	}()
	for worker := 0; worker < readers; worker++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			<-start
			for i := 0; i < 48; i++ {
				if _, err := ListProfiles(); err != nil {
					errs <- fmt.Errorf("list profiles: %w", err)
					return
				}
				if _, err := LoadProfile("alpha"); err != nil {
					errs <- fmt.Errorf("load profile: %w", err)
					return
				}
				if _, err := LoadGlobalProxy(); err != nil {
					errs <- fmt.Errorf("load global proxy: %w", err)
					return
				}
				if _, err := LoadConfigBackupSettings(); err != nil {
					errs <- fmt.Errorf("load backup settings: %w", err)
					return
				}
			}
		}()
	}
	close(start)
	workers.Wait()
	close(errs)
	for err := range errs {
		t.Error(err)
	}
	assertConfigDBConsistent(t)
}

func assertConfigDBConsistent(t *testing.T) {
	t.Helper()
	db, release, err := acquireConfigDB()
	if err != nil {
		t.Fatalf("acquire config db for check: %v", err)
	}
	defer release()
	if err := db.View(func(tx *bolt.Tx) error {
		for checkErr := range tx.Check() {
			return checkErr
		}
		return nil
	}); err != nil {
		t.Fatalf("config.db integrity check: %v", err)
	}
}
