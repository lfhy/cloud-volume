//go:build windows && cgo

// Windows Cloud Files provider wraps the minimal CFAPI lifecycle needed by this app.
package mount

// #cgo CFLAGS: -I. -D_AMD64_ -D_M_AMD64=100 -DWIN64 -D_WIN32_WINNT=0x0A00
// #cgo LDFLAGS: -lole32
// #include "cloud_files_windows.h"
// #include <stdlib.h>
import "C"

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
	"unsafe"
)

const (
	cloudFilesAlreadyExists = uint32(0x800700b7)
	cloudFilesNotACloudFile = uint32(0x80070178)
	cloudFilesUserMapped    = uint32(0x800704c8)
)

var (
	cloudProviderMu       sync.RWMutex
	cloudProviderRegistry = map[int64]*cloudFilesProvider{}
)

type cloudFilesProvider struct {
	localPath   string
	providerID  string
	displayName string

	mu            sync.Mutex
	connectionKey int64
	callbacks     cloudFilesCallbacks
}

func newCloudFilesProvider(localPath, providerID, displayName string) *cloudFilesProvider {
	return &cloudFilesProvider{
		localPath:   localPath,
		providerID:  providerID,
		displayName: displayName,
	}
}

func (p *cloudFilesProvider) Register() error {
	wPath, freePath := cloudFilesWideString(p.localPath)
	defer freePath()
	wProviderID, freeProviderID := cloudFilesWideString(p.providerID)
	defer freeProviderID()
	wDisplayName, freeDisplayName := cloudFilesWideString(p.displayName)
	defer freeDisplayName()

	hr := C.rs_cf_register(wPath, wProviderID, wDisplayName)
	if hr != 0 {
		return fmt.Errorf("register Cloud Files sync root: HRESULT 0x%08x", uint32(hr))
	}
	return nil
}

func (p *cloudFilesProvider) Deregister() error {
	wPath, freePath := cloudFilesWideString(p.localPath)
	defer freePath()

	hr := C.rs_cf_deregister(wPath)
	if hr != 0 {
		return fmt.Errorf("deregister Cloud Files sync root: HRESULT 0x%08x", uint32(hr))
	}
	return nil
}

func (p *cloudFilesProvider) Connect(callbacks cloudFilesCallbacks) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	wPath, freePath := cloudFilesWideString(p.localPath)
	defer freePath()

	var key C.rs_connection_key_t
	hr := C.rs_cf_connect(wPath, &key)
	if hr != 0 {
		return fmt.Errorf("connect Cloud Files sync root: HRESULT 0x%08x", uint32(hr))
	}
	p.connectionKey = int64(key)
	p.callbacks = callbacks

	cloudProviderMu.Lock()
	cloudProviderRegistry[p.connectionKey] = p
	cloudProviderMu.Unlock()
	return nil
}

func (p *cloudFilesProvider) Disconnect() error {
	p.mu.Lock()
	key := p.connectionKey
	p.connectionKey = 0
	p.mu.Unlock()

	if key == 0 {
		return nil
	}

	cloudProviderMu.Lock()
	delete(cloudProviderRegistry, key)
	cloudProviderMu.Unlock()

	hr := C.rs_cf_disconnect(C.rs_connection_key_t(key))
	if hr != 0 {
		return fmt.Errorf("disconnect Cloud Files sync root: HRESULT 0x%08x", uint32(hr))
	}
	return nil
}

func (p *cloudFilesProvider) IsConnected() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.connectionKey != 0
}

func (p *cloudFilesProvider) CreatePlaceholders(baseDir string, items []cloudPlaceholderInfo) error {
	if len(items) == 0 {
		return nil
	}
	wBaseDir, freeBaseDir := cloudFilesWideString(baseDir)
	defer freeBaseDir()

	for _, item := range items {
		localPath := filepath.Join(baseDir, filepath.FromSlash(item.RelativePath))
		if _, err := os.Lstat(localPath); err == nil {
			continue
		} else if !os.IsNotExist(err) {
			return fmt.Errorf("stat placeholder target %q: %w", item.RelativePath, err)
		}

		var createInfo C.CF_PLACEHOLDER_CREATE_INFO

		wRelativePath, freeRelativePath := cloudFilesWideString(item.RelativePath)
		createInfo.RelativeFileName = C.LPCWSTR(wRelativePath)
		*(*C.LONGLONG)(unsafe.Pointer(&createInfo.FsMetadata.FileSize)) = C.LONGLONG(item.FileSize)
		createInfo.Flags = C.CF_PLACEHOLDER_CREATE_FLAG_MARK_IN_SYNC
		fileTime := cloudFilesTimeToFileTime(item.ModTime)
		createInfo.FsMetadata.BasicInfo.CreationTime = fileTime
		createInfo.FsMetadata.BasicInfo.LastWriteTime = fileTime
		createInfo.FsMetadata.BasicInfo.LastAccessTime = fileTime
		createInfo.FsMetadata.BasicInfo.ChangeTime = fileTime
		if item.IsDirectory {
			createInfo.FsMetadata.BasicInfo.FileAttributes = C.FILE_ATTRIBUTE_DIRECTORY
		} else {
			createInfo.FsMetadata.BasicInfo.FileAttributes =
				C.FILE_ATTRIBUTE_ARCHIVE | C.FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS
		}

		var identity *C.char
		if item.FileID != "" {
			identity = C.CString(item.FileID)
			createInfo.FileIdentityLength = C.DWORD(len(item.FileID))
			createInfo.FileIdentity = C.LPCVOID(unsafe.Pointer(identity))
		}

		var created C.DWORD
		hr := C.rs_cf_create_placeholders(wBaseDir, &createInfo, 1, &created)

		freeRelativePath()
		if identity != nil {
			C.free(unsafe.Pointer(identity))
		}

		switch uint32(hr) {
		case 0, cloudFilesAlreadyExists, cloudFilesUserMapped:
			continue
		default:
			return fmt.Errorf("create placeholder %q: HRESULT 0x%08x", item.RelativePath, uint32(hr))
		}
	}
	return nil
}

func (p *cloudFilesProvider) SetInSync(localPath string, inSync bool) error {
	wPath, freePath := cloudFilesWideString(localPath)
	defer freePath()

	state := C.int(0)
	if inSync {
		state = 1
	}
	hr := C.rs_cf_set_sync_state(wPath, state)
	if hr != 0 {
		if uint32(hr) == cloudFilesNotACloudFile {
			// Local-first writes can temporarily stay as regular NTFS files, so
			// native Cloud Files sync-state projection is best-effort here.
			return nil
		}
		return fmt.Errorf("set Cloud Files sync state: HRESULT 0x%08x", uint32(hr))
	}
	return nil
}

func (p *cloudFilesProvider) ExecuteTransfer(
	offsetValue int64,
	req cloudFilesFetchRequest,
	data []byte,
) error {
	if req.opInfo == 0 {
		return fmt.Errorf("missing Cloud Files callback info")
	}
	var offset C.LARGE_INTEGER
	var length C.LARGE_INTEGER
	*(*C.LONGLONG)(unsafe.Pointer(&offset)) = C.LONGLONG(offsetValue)
	*(*C.LONGLONG)(unsafe.Pointer(&length)) = C.LONGLONG(len(data))

	var dataPtr *C.BYTE
	if len(data) > 0 {
		dataPtr = (*C.BYTE)(unsafe.Pointer(&data[0]))
	}
	hr := C.rs_cf_execute_transfer(C.uintptr_t(req.opInfo), offset, length, dataPtr)
	if hr != 0 {
		return fmt.Errorf("execute Cloud Files transfer: HRESULT 0x%08x", uint32(hr))
	}
	return nil
}

func (p *cloudFilesProvider) ReportError(req cloudFilesFetchRequest, err error) error {
	if req.opInfo == 0 {
		return nil
	}
	_ = err
	hr := C.rs_cf_report_error(C.uintptr_t(req.opInfo), C.HRESULT(-2147467259))
	if hr != 0 {
		return fmt.Errorf("report Cloud Files transfer error: HRESULT 0x%08x", uint32(hr))
	}
	return nil
}

func (p *cloudFilesProvider) AckPlaceholders(opInfo uintptr, callbackErr error) error {
	status := C.HRESULT(0)
	if callbackErr != nil {
		status = C.HRESULT(-2147467259)
	}
	hr := C.rs_cf_ack_placeholders(C.uintptr_t(opInfo), status)
	if hr != 0 {
		return fmt.Errorf("ack Cloud Files placeholders: HRESULT 0x%08x", uint32(hr))
	}
	return nil
}

func (p *cloudFilesProvider) CompletePlaceholders(
	opInfo uintptr,
	callbackErr error,
	disableOnDemandPopulation bool,
) error {
	status := C.HRESULT(0)
	if callbackErr != nil {
		status = C.HRESULT(-2147467259)
	}
	flags := C.DWORD(C.CF_OPERATION_TRANSFER_PLACEHOLDERS_FLAG_NONE)
	if callbackErr == nil && disableOnDemandPopulation {
		flags = C.DWORD(
			C.CF_OPERATION_TRANSFER_PLACEHOLDERS_FLAG_DISABLE_ON_DEMAND_POPULATION,
		)
	}
	hr := C.rs_cf_complete_placeholders(C.uintptr_t(opInfo), status, flags)
	if hr != 0 {
		return fmt.Errorf("complete Cloud Files placeholders: HRESULT 0x%08x", uint32(hr))
	}
	return nil
}

func (p *cloudFilesProvider) ReportProgress(req cloudFilesFetchRequest, total, done int64) error {
	if req.opInfo == 0 {
		return nil
	}
	var totalValue C.LARGE_INTEGER
	var doneValue C.LARGE_INTEGER
	*(*C.LONGLONG)(unsafe.Pointer(&totalValue)) = C.LONGLONG(total)
	*(*C.LONGLONG)(unsafe.Pointer(&doneValue)) = C.LONGLONG(done)
	hr := C.rs_cf_report_progress_cb(C.uintptr_t(req.opInfo), totalValue, doneValue)
	if hr != 0 {
		return fmt.Errorf("report Cloud Files progress: HRESULT 0x%08x", uint32(hr))
	}
	return nil
}

func cloudFilesWideString(value string) (*C.WCHAR, func()) {
	cString := C.CString(value)
	wide := C.rs_utf8_to_wchar(cString)
	return wide, func() {
		C.free(unsafe.Pointer(cString))
		if wide != nil {
			C.rs_free_wchar(wide)
		}
	}
}

func cloudFilesTimeToFileTime(value time.Time) C.LARGE_INTEGER {
	const windowsEpochDelta = int64(116444736000000000)
	ticks := value.UnixNano()/100 + windowsEpochDelta
	var result C.LARGE_INTEGER
	*(*C.LONGLONG)(unsafe.Pointer(&result)) = C.LONGLONG(ticks)
	return result
}
