//go:build windows && cgo

// Cloud Files callbacks bridge the native CFAPI events back into the Go provider.
package mount

// #cgo CFLAGS: -I. -D_AMD64_ -D_M_AMD64=100 -DWIN64 -D_WIN32_WINNT=0x0A00
// #include "cloud_files_windows.h"
import "C"

import (
	"log"
	"path/filepath"
	"strings"
	"unsafe"
)

func cloudFilesProviderForKey(key int64) *cloudFilesProvider {
	cloudProviderMu.RLock()
	defer cloudProviderMu.RUnlock()
	return cloudProviderRegistry[key]
}

func cloudFilesResolvePath(info *C.CF_CALLBACK_INFO, syncRoot string) string {
	if info == nil || info.NormalizedPath == nil {
		return ""
	}
	utf8 := C.rs_wchar_to_utf8(info.NormalizedPath)
	if utf8 == nil {
		return ""
	}
	defer C.rs_free_utf8(utf8)

	path := C.GoString(utf8)
	if path == "" {
		return ""
	}
	if strings.HasPrefix(path, `\`) && !strings.HasPrefix(path, `\\`) && len(syncRoot) >= 2 && syncRoot[1] == ':' {
		path = syncRoot[:2] + path
	}
	return filepath.Clean(path)
}

func cloudFilesRenameSource(params *C.CF_CALLBACK_PARAMETERS, syncRoot string) string {
	if params == nil {
		return ""
	}
	utf8 := C.rs_rename_source_path(params)
	if utf8 == nil {
		return ""
	}
	defer C.rs_free_utf8(utf8)

	path := C.GoString(utf8)
	if strings.HasPrefix(path, `\`) && !strings.HasPrefix(path, `\\`) && len(syncRoot) >= 2 && syncRoot[1] == ':' {
		path = syncRoot[:2] + path
	}
	return filepath.Clean(path)
}

//export rsOnFetchData
func rsOnFetchData(callbackInfoPtr uintptr, paramsPtr uintptr) {
	if callbackInfoPtr == 0 {
		return
	}
	info := (*C.CF_CALLBACK_INFO)(unsafe.Pointer(callbackInfoPtr))
	provider := cloudFilesProviderForKey(int64(info.ConnectionKey.Internal))
	if provider == nil || provider.callbacks.OnFetchData == nil {
		return
	}

	req := cloudFilesFetchRequest{
		LocalPath: cloudFilesResolvePath(info, provider.localPath),
		FileSize:  int64(*(*C.LONGLONG)(unsafe.Pointer(&info.FileSize))),
		Offset:    int64(C.rs_fetch_data_offset((*C.CF_CALLBACK_PARAMETERS)(unsafe.Pointer(paramsPtr)))),
		Length:    int64(C.rs_fetch_data_length((*C.CF_CALLBACK_PARAMETERS)(unsafe.Pointer(paramsPtr)))),
		opInfo:    callbackInfoPtr,
	}
	if err := provider.callbacks.OnFetchData(req); err != nil {
		log.Printf("[mount/cloud-files] fetch-data-callback local=%q error=%v", req.LocalPath, err)
	}
}

//export rsOnCancelFetch
func rsOnCancelFetch(callbackInfoPtr uintptr, _ uintptr) {
	if callbackInfoPtr == 0 {
		return
	}
	info := (*C.CF_CALLBACK_INFO)(unsafe.Pointer(callbackInfoPtr))
	provider := cloudFilesProviderForKey(int64(info.ConnectionKey.Internal))
	if provider == nil || provider.callbacks.OnCancelFetch == nil {
		return
	}
	provider.callbacks.OnCancelFetch(cloudFilesFetchRequest{
		LocalPath: cloudFilesResolvePath(info, provider.localPath),
	})
}

//export rsOnFetchPlaceholders
func rsOnFetchPlaceholders(callbackInfoPtr uintptr, _ uintptr) {
	if callbackInfoPtr == 0 {
		return
	}
	info := (*C.CF_CALLBACK_INFO)(unsafe.Pointer(callbackInfoPtr))
	provider := cloudFilesProviderForKey(int64(info.ConnectionKey.Internal))
	if provider == nil || provider.callbacks.OnFetchPlaceholders == nil {
		return
	}
	err := provider.callbacks.OnFetchPlaceholders(cloudFilesResolvePath(info, provider.localPath))
	if err != nil {
		log.Printf("[mount/cloud-files] fetch-placeholders-callback error=%v", err)
	}
	_ = provider.CompletePlaceholders(callbackInfoPtr, err, err == nil)
}

//export rsOnDeleteCompletion
func rsOnDeleteCompletion(callbackInfoPtr uintptr, _ uintptr) {
	if callbackInfoPtr == 0 {
		return
	}
	info := (*C.CF_CALLBACK_INFO)(unsafe.Pointer(callbackInfoPtr))
	provider := cloudFilesProviderForKey(int64(info.ConnectionKey.Internal))
	if provider == nil || provider.callbacks.OnDeleteCompletion == nil {
		return
	}
	provider.callbacks.OnDeleteCompletion(cloudFilesResolvePath(info, provider.localPath))
}

//export rsOnRenameCompletion
func rsOnRenameCompletion(callbackInfoPtr uintptr, paramsPtr uintptr) {
	if callbackInfoPtr == 0 {
		return
	}
	info := (*C.CF_CALLBACK_INFO)(unsafe.Pointer(callbackInfoPtr))
	provider := cloudFilesProviderForKey(int64(info.ConnectionKey.Internal))
	if provider == nil || provider.callbacks.OnRenameCompletion == nil {
		return
	}
	newPath := cloudFilesResolvePath(info, provider.localPath)
	oldPath := cloudFilesRenameSource((*C.CF_CALLBACK_PARAMETERS)(unsafe.Pointer(paramsPtr)), provider.localPath)
	if oldPath == "" {
		oldPath = newPath
	}
	provider.callbacks.OnRenameCompletion(oldPath, newPath)
}
