#ifdef _WIN32

#include "cloud_files_windows.h"
#include <objbase.h>
#include <stdlib.h>

typedef HRESULT (WINAPI *rs_cf_register_fn)(
    LPCWSTR,
    const CF_SYNC_REGISTRATION*,
    const CF_SYNC_POLICIES*,
    CF_REGISTER_FLAGS);
typedef HRESULT (WINAPI *rs_cf_deregister_fn)(LPCWSTR);
typedef HRESULT (WINAPI *rs_cf_connect_fn)(
    LPCWSTR,
    const CF_CALLBACK_REGISTRATION*,
    LPCVOID,
    CF_CONNECT_FLAGS,
    CF_CONNECTION_KEY*);
typedef HRESULT (WINAPI *rs_cf_disconnect_fn)(CF_CONNECTION_KEY);
typedef HRESULT (WINAPI *rs_cf_create_placeholders_fn)(
    LPCWSTR,
    CF_PLACEHOLDER_CREATE_INFO*,
    DWORD,
    CF_CREATE_FLAGS,
    PDWORD);
typedef HRESULT (WINAPI *rs_cf_set_in_sync_fn)(
    HANDLE,
    CF_IN_SYNC_STATE,
    CF_SET_IN_SYNC_FLAGS,
    USN*);
typedef HRESULT (WINAPI *rs_cf_execute_fn)(
    const CF_OPERATION_INFO*,
    CF_OPERATION_PARAMETERS*);
typedef HRESULT (WINAPI *rs_cf_report_progress_fn)(
    CF_CONNECTION_KEY,
    CF_TRANSFER_KEY,
    LARGE_INTEGER,
    LARGE_INTEGER);

static HMODULE rs_cf_module = NULL;

static FARPROC rs_load_proc(const char* name) {
    if (!rs_cf_module) {
        rs_cf_module = LoadLibraryW(L"cldapi.dll");
    }
    if (!rs_cf_module) {
        return NULL;
    }
    return GetProcAddress(rs_cf_module, name);
}

LPWSTR rs_utf8_to_wchar(const char* utf8) {
    if (!utf8) return NULL;
    int len = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
    if (len <= 0) return NULL;
    LPWSTR wstr = (LPWSTR)malloc(len * sizeof(WCHAR));
    if (!wstr) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, utf8, -1, wstr, len);
    return wstr;
}

void rs_free_wchar(LPWSTR wstr) {
    free(wstr);
}

char* rs_wchar_to_utf8(LPCWSTR wstr) {
    if (!wstr) return NULL;
    int len = WideCharToMultiByte(CP_UTF8, 0, wstr, -1, NULL, 0, NULL, NULL);
    if (len <= 0) return NULL;
    char* utf8 = (char*)malloc(len);
    if (!utf8) return NULL;
    WideCharToMultiByte(CP_UTF8, 0, wstr, -1, utf8, len, NULL, NULL);
    return utf8;
}

void rs_free_utf8(char* str) {
    free(str);
}

HRESULT rs_cf_register(LPCWSTR syncRootPath, LPCWSTR providerID, LPCWSTR displayName) {
    rs_cf_register_fn fn = (rs_cf_register_fn)rs_load_proc("CfRegisterSyncRoot");
    if (!fn) return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);

    CF_SYNC_REGISTRATION reg = {0};
    reg.StructSize = sizeof(reg);
    reg.ProviderName = displayName;
    reg.ProviderVersion = L"1.0";

    static const BYTE syncIdentity[1] = {0x01};
    reg.SyncRootIdentity = syncIdentity;
    reg.SyncRootIdentityLength = 1;

    HRESULT hr = CLSIDFromString(providerID, &reg.ProviderId);
    if (FAILED(hr)) return hr;

    CF_SYNC_POLICIES policies = {0};
    policies.StructSize = sizeof(policies);
    policies.Hydration.Primary = (USHORT)CF_HYDRATION_POLICY_PROGRESSIVE;
    policies.Population.Primary = (USHORT)CF_POPULATION_POLICY_PARTIAL;
    policies.InSync = CF_INSYNC_POLICY_TRACK_FILE_CREATION_TIME |
                      CF_INSYNC_POLICY_TRACK_FILE_LAST_WRITE_TIME;
    policies.HardLink = CF_HARDLINK_POLICY_NONE;
    policies.PlaceholderManagement = CF_PLACEHOLDER_MANAGEMENT_POLICY_DEFAULT;

    return fn(syncRootPath, &reg, &policies, CF_REGISTER_FLAG_NONE);
}

HRESULT rs_cf_deregister(LPCWSTR syncRootPath) {
    rs_cf_deregister_fn fn = (rs_cf_deregister_fn)rs_load_proc("CfUnregisterSyncRoot");
    if (!fn) return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
    return fn(syncRootPath);
}

extern void rsOnFetchData(uintptr_t callbackInfoPtr, uintptr_t paramsPtr);
extern void rsOnCancelFetch(uintptr_t callbackInfoPtr, uintptr_t paramsPtr);
extern void rsOnFetchPlaceholders(uintptr_t callbackInfoPtr, uintptr_t paramsPtr);
extern void rsOnDeleteCompletion(uintptr_t callbackInfoPtr, uintptr_t paramsPtr);
extern void rsOnRenameCompletion(uintptr_t callbackInfoPtr, uintptr_t paramsPtr);

static void CALLBACK rs_cb_fetch_data(
        const CF_CALLBACK_INFO* info,
        const CF_CALLBACK_PARAMETERS* params) {
    rsOnFetchData((uintptr_t)info, (uintptr_t)params);
}

static void CALLBACK rs_cb_cancel_fetch(
        const CF_CALLBACK_INFO* info,
        const CF_CALLBACK_PARAMETERS* params) {
    rsOnCancelFetch((uintptr_t)info, (uintptr_t)params);
}

static void CALLBACK rs_cb_fetch_placeholders(
        const CF_CALLBACK_INFO* info,
        const CF_CALLBACK_PARAMETERS* params) {
    rsOnFetchPlaceholders((uintptr_t)info, (uintptr_t)params);
}

static void CALLBACK rs_cb_delete_completion(
        const CF_CALLBACK_INFO* info,
        const CF_CALLBACK_PARAMETERS* params) {
    rsOnDeleteCompletion((uintptr_t)info, (uintptr_t)params);
}

static void CALLBACK rs_cb_rename_completion(
        const CF_CALLBACK_INFO* info,
        const CF_CALLBACK_PARAMETERS* params) {
    rsOnRenameCompletion((uintptr_t)info, (uintptr_t)params);
}

HRESULT rs_cf_connect(LPCWSTR localPath, rs_connection_key_t* outKey) {
    rs_cf_connect_fn fn = (rs_cf_connect_fn)rs_load_proc("CfConnectSyncRoot");
    if (!fn) return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);

    CF_CALLBACK_REGISTRATION callbacks[] = {
        { CF_CALLBACK_TYPE_FETCH_DATA, rs_cb_fetch_data },
        { CF_CALLBACK_TYPE_CANCEL_FETCH_DATA, rs_cb_cancel_fetch },
        { CF_CALLBACK_TYPE_FETCH_PLACEHOLDERS, rs_cb_fetch_placeholders },
        { CF_CALLBACK_TYPE_NOTIFY_DELETE_COMPLETION, rs_cb_delete_completion },
        { CF_CALLBACK_TYPE_NOTIFY_RENAME_COMPLETION, rs_cb_rename_completion },
        CF_CALLBACK_REGISTRATION_END
    };

    CF_CONNECTION_KEY key = {0};
    HRESULT hr = fn(
        localPath,
        callbacks,
        NULL,
        CF_CONNECT_FLAG_REQUIRE_PROCESS_INFO | CF_CONNECT_FLAG_REQUIRE_FULL_FILE_PATH,
        &key);
    if (SUCCEEDED(hr) && outKey) {
        *outKey = key.Internal;
    }
    return hr;
}

HRESULT rs_cf_disconnect(rs_connection_key_t key) {
    rs_cf_disconnect_fn fn = (rs_cf_disconnect_fn)rs_load_proc("CfDisconnectSyncRoot");
    if (!fn) return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
    CF_CONNECTION_KEY connectionKey = {0};
    connectionKey.Internal = key;
    return fn(connectionKey);
}

HRESULT rs_cf_create_placeholders(
        LPCWSTR localPath,
        CF_PLACEHOLDER_CREATE_INFO* items,
        DWORD count,
        DWORD* outCreated) {
    rs_cf_create_placeholders_fn fn = (rs_cf_create_placeholders_fn)rs_load_proc("CfCreatePlaceholders");
    if (!fn) return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
    return fn(localPath, items, count, CF_CREATE_FLAG_NONE, outCreated);
}

HRESULT rs_cf_set_sync_state(LPCWSTR localPath, int state) {
    rs_cf_set_in_sync_fn fn = (rs_cf_set_in_sync_fn)rs_load_proc("CfSetInSyncState");
    if (!fn) return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);

    HANDLE handle = CreateFileW(
        localPath,
        FILE_WRITE_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        NULL,
        OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS,
        NULL);
    if (handle == INVALID_HANDLE_VALUE) {
        return HRESULT_FROM_WIN32(GetLastError());
    }

    HRESULT hr = fn(
        handle,
        state == 0 ? CF_IN_SYNC_STATE_NOT_IN_SYNC : CF_IN_SYNC_STATE_IN_SYNC,
        CF_SET_IN_SYNC_FLAG_NONE,
        NULL);
    CloseHandle(handle);
    return hr;
}

static CF_OPERATION_INFO rs_build_op_info(
        const CF_CALLBACK_INFO* info,
        CF_OPERATION_TYPE type) {
    CF_OPERATION_INFO opInfo = {0};
    opInfo.StructSize = sizeof(CF_OPERATION_INFO);
    opInfo.Type = type;
    opInfo.ConnectionKey = info->ConnectionKey;
    opInfo.TransferKey = info->TransferKey;
    opInfo.RequestKey = info->RequestKey;
    return opInfo;
}

HRESULT rs_cf_execute_transfer(
        uintptr_t callbackInfoPtr,
        LARGE_INTEGER offset,
        LARGE_INTEGER length,
        const BYTE* data) {
    rs_cf_execute_fn fn = (rs_cf_execute_fn)rs_load_proc("CfExecute");
    if (!fn) return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
    if (!callbackInfoPtr) return E_INVALIDARG;

    const CF_CALLBACK_INFO* info = (const CF_CALLBACK_INFO*)callbackInfoPtr;
    CF_OPERATION_INFO opInfo = rs_build_op_info(info, CF_OPERATION_TYPE_TRANSFER_DATA);
    CF_OPERATION_PARAMETERS params = {0};
    params.ParamSize = RS_SIZE_OF_OP_PARAM(TransferData);
    params.TransferData.Flags = CF_OPERATION_TRANSFER_DATA_FLAG_NONE;
    params.TransferData.CompletionStatus = S_OK;
    params.TransferData.Buffer = data;
    params.TransferData.Offset = offset;
    params.TransferData.Length = length;
    return fn(&opInfo, &params);
}

HRESULT rs_cf_report_error(uintptr_t callbackInfoPtr, HRESULT providerError) {
    rs_cf_execute_fn fn = (rs_cf_execute_fn)rs_load_proc("CfExecute");
    if (!fn) return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
    if (!callbackInfoPtr) return E_INVALIDARG;

    const CF_CALLBACK_INFO* info = (const CF_CALLBACK_INFO*)callbackInfoPtr;
    CF_OPERATION_INFO opInfo = rs_build_op_info(info, CF_OPERATION_TYPE_TRANSFER_DATA);
    CF_OPERATION_PARAMETERS params = {0};
    params.ParamSize = RS_SIZE_OF_OP_PARAM(TransferData);
    params.TransferData.Flags = CF_OPERATION_TRANSFER_DATA_FLAG_NONE;
    params.TransferData.CompletionStatus = providerError;
    return fn(&opInfo, &params);
}

HRESULT rs_cf_ack_placeholders(uintptr_t callbackInfoPtr, HRESULT completionStatus) {
    rs_cf_execute_fn fn = (rs_cf_execute_fn)rs_load_proc("CfExecute");
    if (!fn) return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
    if (!callbackInfoPtr) return E_INVALIDARG;

    const CF_CALLBACK_INFO* info = (const CF_CALLBACK_INFO*)callbackInfoPtr;
    CF_OPERATION_INFO opInfo = rs_build_op_info(info, CF_OPERATION_TYPE_TRANSFER_PLACEHOLDERS);
    CF_OPERATION_PARAMETERS params = {0};
    params.ParamSize = RS_SIZE_OF_OP_PARAM(TransferPlaceholders);
    params.TransferPlaceholders.Flags = CF_OPERATION_TRANSFER_PLACEHOLDERS_FLAG_NONE;
    params.TransferPlaceholders.CompletionStatus = completionStatus;
    return fn(&opInfo, &params);
}

HRESULT rs_cf_complete_placeholders(
        uintptr_t callbackInfoPtr,
        HRESULT completionStatus,
        DWORD flags) {
    rs_cf_execute_fn fn = (rs_cf_execute_fn)rs_load_proc("CfExecute");
    if (!fn) return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
    if (!callbackInfoPtr) return E_INVALIDARG;

    const CF_CALLBACK_INFO* info = (const CF_CALLBACK_INFO*)callbackInfoPtr;
    CF_OPERATION_INFO opInfo = rs_build_op_info(info, CF_OPERATION_TYPE_TRANSFER_PLACEHOLDERS);
    CF_OPERATION_PARAMETERS params = {0};
    params.ParamSize = RS_SIZE_OF_OP_PARAM(TransferPlaceholders);
    params.TransferPlaceholders.Flags = (CF_OPERATION_TRANSFER_PLACEHOLDERS_FLAGS)flags;
    params.TransferPlaceholders.CompletionStatus = completionStatus;
    params.TransferPlaceholders.PlaceholderTotalCount.QuadPart = 0;
    params.TransferPlaceholders.PlaceholderArray = NULL;
    params.TransferPlaceholders.PlaceholderCount = 0;
    params.TransferPlaceholders.EntriesProcessed = 0;
    return fn(&opInfo, &params);
}

HRESULT rs_cf_report_progress_cb(
        uintptr_t callbackInfoPtr,
        LARGE_INTEGER total,
        LARGE_INTEGER done) {
    rs_cf_report_progress_fn fn = (rs_cf_report_progress_fn)rs_load_proc("CfReportProviderProgress");
    if (!fn) return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
    if (!callbackInfoPtr) return E_INVALIDARG;

    const CF_CALLBACK_INFO* info = (const CF_CALLBACK_INFO*)callbackInfoPtr;
    return fn(info->ConnectionKey, info->TransferKey, total, done);
}

LONGLONG rs_fetch_data_offset(const CF_CALLBACK_PARAMETERS* params) {
    if (!params) return 0;
    return params->FetchData.RequiredFileOffset.QuadPart;
}

LONGLONG rs_fetch_data_length(const CF_CALLBACK_PARAMETERS* params) {
    if (!params) return 0;
    return params->FetchData.RequiredLength.QuadPart;
}

char* rs_rename_source_path(const CF_CALLBACK_PARAMETERS* params) {
    if (!params || !params->RenameCompletion.SourcePath) return NULL;
    return rs_wchar_to_utf8(params->RenameCompletion.SourcePath);
}

#endif
