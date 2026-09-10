//go:build windows && cgo

// Cloud Files placeholder callback transfer owns the C array lifetime for CfExecute.
package mount

// #cgo amd64 CFLAGS: -I. -D_AMD64_ -D_M_AMD64=100 -DWIN64 -D_WIN32_WINNT=0x0A00
// #cgo arm64 CFLAGS: -I. -D_ARM64_ -D_M_ARM64=1 -DWIN64 -D_WIN32_WINNT=0x0A00
// #include "cloud_files_windows.h"
// #include <stdlib.h>
import "C"

import (
	"fmt"
	"unsafe"
)

// TransferPlaceholders completes FETCH_PLACEHOLDERS with the real child list.
// The C-owned array must outlive the synchronous CfExecute call because its
// strings, file identities, and metadata are read by CFAPI during that call.
func (p *cloudFilesProvider) TransferPlaceholders(
	opInfo uintptr,
	placeholders []cloudPlaceholderInfo,
	callbackErr error,
) error {
	if opInfo == 0 {
		return fmt.Errorf("missing Cloud Files placeholder callback info")
	}
	plan := cloudFilesPlaceholderTransferPlanFor(placeholders, callbackErr)
	status := C.NTSTATUS(0)
	if callbackErr != nil {
		status = C.NTSTATUS(-1073741823) // STATUS_UNSUCCESSFUL (0xC0000001)
	}
	flags := C.DWORD(C.CF_OPERATION_TRANSFER_PLACEHOLDERS_FLAG_NONE)
	if plan.stopOnError {
		flags |= C.DWORD(C.CF_OPERATION_TRANSFER_PLACEHOLDERS_FLAG_STOP_ON_ERROR)
	}
	if plan.disableOnDemandPopulation {
		flags |= C.DWORD(
			C.CF_OPERATION_TRANSFER_PLACEHOLDERS_FLAG_DISABLE_ON_DEMAND_POPULATION,
		)
	}
	return cloudFilesWithPlaceholderCreateInfos(
		plan.placeholders,
		func(createInfos *C.CF_PLACEHOLDER_CREATE_INFO, count C.DWORD) error {
			var entriesProcessed C.DWORD
			hr := C.rs_cf_transfer_placeholders(
				C.uintptr_t(opInfo),
				status,
				flags,
				C.LONGLONG(plan.totalCount),
				createInfos,
				count,
				&entriesProcessed,
			)
			if hr != 0 {
				return fmt.Errorf(
					"transfer Cloud Files placeholders: HRESULT 0x%08x",
					uint32(hr),
				)
			}
			if entriesProcessed != count {
				return fmt.Errorf(
					"Cloud Files processed %d of %d placeholders",
					entriesProcessed,
					count,
				)
			}
			if err := cloudFilesPlaceholderCreateResults(createInfos, plan.placeholders); err != nil {
				return err
			}
			return nil
		},
	)
}

func cloudFilesPlaceholderCreateResults(
	createInfos *C.CF_PLACEHOLDER_CREATE_INFO,
	placeholders []cloudPlaceholderInfo,
) error {
	if len(placeholders) == 0 {
		return nil
	}
	infos := unsafe.Slice(createInfos, len(placeholders))
	for index, info := range infos {
		if info.Result != 0 {
			return fmt.Errorf(
				"transfer Cloud Files placeholder %q: HRESULT 0x%08x",
				placeholders[index].RelativePath,
				uint32(info.Result),
			)
		}
	}
	return nil
}

func cloudFilesWithPlaceholderCreateInfos(
	placeholders []cloudPlaceholderInfo,
	invoke func(*C.CF_PLACEHOLDER_CREATE_INFO, C.DWORD) error,
) error {
	if len(placeholders) == 0 {
		return invoke(nil, 0)
	}
	if uint64(len(placeholders)) > uint64(^uint32(0)) {
		return fmt.Errorf("too many Cloud Files placeholders: %d", len(placeholders))
	}

	createInfoBytes := C.size_t(C.sizeof_CF_PLACEHOLDER_CREATE_INFO)
	createInfos := C.calloc(C.size_t(len(placeholders)), createInfoBytes)
	if createInfos == nil {
		return fmt.Errorf("allocate Cloud Files placeholder transfer array")
	}
	defer C.free(createInfos)

	infos := unsafe.Slice(
		(*C.CF_PLACEHOLDER_CREATE_INFO)(createInfos),
		len(placeholders),
	)
	freeNames := make([]func(), 0, len(placeholders))
	identities := make([]*C.char, 0, len(placeholders))
	defer func() {
		for _, freeName := range freeNames {
			freeName()
		}
		for _, identity := range identities {
			C.free(unsafe.Pointer(identity))
		}
	}()

	for index, placeholder := range placeholders {
		name, freeName := cloudFilesWideString(placeholder.RelativePath)
		if name == nil {
			freeName()
			return fmt.Errorf(
				"encode Cloud Files placeholder name %q",
				placeholder.RelativePath,
			)
		}
		freeNames = append(freeNames, freeName)
		infos[index].RelativeFileName = C.LPCWSTR(name)
		infos[index].FsMetadata = cloudFilesPlaceholderMetadata(placeholder)
		infos[index].Flags = C.CF_PLACEHOLDER_CREATE_FLAG_MARK_IN_SYNC
		if placeholder.FileID == "" {
			continue
		}
		identity := C.CString(placeholder.FileID)
		if identity == nil {
			return fmt.Errorf(
				"allocate Cloud Files placeholder identity %q",
				placeholder.RelativePath,
			)
		}
		identities = append(identities, identity)
		infos[index].FileIdentity = C.LPCVOID(unsafe.Pointer(identity))
		infos[index].FileIdentityLength = C.DWORD(len(placeholder.FileID))
	}

	return invoke(&infos[0], C.DWORD(len(infos)))
}
