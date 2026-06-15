#ifndef REMOTE_STORAGE_CLOUD_FILES_WINDOWS_H
#define REMOTE_STORAGE_CLOUD_FILES_WINDOWS_H

#include <windows.h>
#include <stdint.h>

typedef struct RS_CF_CONNECTION_KEY {
    LONGLONG Internal;
} CF_CONNECTION_KEY;

typedef LARGE_INTEGER CF_TRANSFER_KEY;
typedef LARGE_INTEGER CF_REQUEST_KEY;

typedef const void* PCORRELATION_VECTOR;
typedef LONG NTSTATUS;

typedef struct RS_CF_FS_METADATA {
    FILE_BASIC_INFO BasicInfo;
    LARGE_INTEGER FileSize;
} CF_FS_METADATA;

typedef enum RS_CF_PLACEHOLDER_CREATE_FLAGS {
    CF_PLACEHOLDER_CREATE_FLAG_NONE = 0x00000000,
    CF_PLACEHOLDER_CREATE_FLAG_MARK_IN_SYNC = 0x00000002,
    CF_PLACEHOLDER_CREATE_FLAG_SUPERSEDE = 0x00000004,
} CF_PLACEHOLDER_CREATE_FLAGS;

typedef struct RS_CF_PLACEHOLDER_CREATE_INFO {
    LPCWSTR RelativeFileName;
    CF_FS_METADATA FsMetadata;
    LPCVOID FileIdentity;
    DWORD FileIdentityLength;
    CF_PLACEHOLDER_CREATE_FLAGS Flags;
    HRESULT Result;
    USN CreateUsn;
} CF_PLACEHOLDER_CREATE_INFO;

typedef enum RS_CF_REGISTER_FLAGS {
    CF_REGISTER_FLAG_NONE = 0x00000000,
} CF_REGISTER_FLAGS;

typedef enum RS_CF_HYDRATION_POLICY_PRIMARY {
    CF_HYDRATION_POLICY_PARTIAL = 0,
    CF_HYDRATION_POLICY_PROGRESSIVE = 1,
    CF_HYDRATION_POLICY_FULL = 2,
    CF_HYDRATION_POLICY_ALWAYS_FULL = 3,
} CF_HYDRATION_POLICY_PRIMARY;

typedef enum RS_CF_POPULATION_POLICY_PRIMARY {
    CF_POPULATION_POLICY_PARTIAL = 0,
    CF_POPULATION_POLICY_FULL = 2,
    CF_POPULATION_POLICY_ALWAYS_FULL = 3,
} CF_POPULATION_POLICY_PRIMARY;

typedef enum RS_CF_INSYNC_POLICY {
    CF_INSYNC_POLICY_TRACK_FILE_CREATION_TIME = 0x00000001,
    CF_INSYNC_POLICY_TRACK_FILE_LAST_WRITE_TIME = 0x00000100,
} CF_INSYNC_POLICY;

typedef enum RS_CF_HARDLINK_POLICY {
    CF_HARDLINK_POLICY_NONE = 0x00000000,
} CF_HARDLINK_POLICY;

typedef enum RS_CF_PLACEHOLDER_MANAGEMENT_POLICY {
    CF_PLACEHOLDER_MANAGEMENT_POLICY_DEFAULT = 0x00000000,
} CF_PLACEHOLDER_MANAGEMENT_POLICY;

typedef struct RS_CF_HYDRATION_POLICY {
    USHORT Primary;
    USHORT Modifier;
} CF_HYDRATION_POLICY;

typedef struct RS_CF_POPULATION_POLICY {
    USHORT Primary;
    USHORT Modifier;
} CF_POPULATION_POLICY;

typedef struct RS_CF_SYNC_POLICIES {
    ULONG StructSize;
    CF_HYDRATION_POLICY Hydration;
    CF_POPULATION_POLICY Population;
    ULONG InSync;
    ULONG HardLink;
    ULONG PlaceholderManagement;
} CF_SYNC_POLICIES;

typedef struct RS_CF_SYNC_REGISTRATION {
    ULONG StructSize;
    LPCWSTR ProviderName;
    LPCWSTR ProviderVersion;
    LPCVOID SyncRootIdentity;
    DWORD SyncRootIdentityLength;
    LPCVOID FileIdentity;
    DWORD FileIdentityLength;
    GUID ProviderId;
} CF_SYNC_REGISTRATION;

typedef struct RS_CF_PROCESS_INFO {
    DWORD StructSize;
    DWORD ProcessId;
    PCWSTR ImagePath;
    PCWSTR PackageName;
    PCWSTR ApplicationId;
    PCWSTR CommandLine;
    DWORD SessionId;
} CF_PROCESS_INFO;

typedef struct RS_CF_CALLBACK_INFO {
    DWORD StructSize;
    CF_CONNECTION_KEY ConnectionKey;
    LPVOID CallbackContext;
    PCWSTR VolumeGuidName;
    PCWSTR VolumeDosName;
    DWORD VolumeSerialNumber;
    LARGE_INTEGER SyncRootFileId;
    LPCVOID SyncRootIdentity;
    DWORD SyncRootIdentityLength;
    LARGE_INTEGER FileId;
    LARGE_INTEGER FileSize;
    LPCVOID FileIdentity;
    DWORD FileIdentityLength;
    PCWSTR NormalizedPath;
    CF_TRANSFER_KEY TransferKey;
    UCHAR PriorityHint;
    PCORRELATION_VECTOR CorrelationVector;
    CF_PROCESS_INFO* ProcessInfo;
    CF_REQUEST_KEY RequestKey;
} CF_CALLBACK_INFO;

typedef enum RS_CF_CALLBACK_FETCH_DATA_FLAGS {
    CF_CALLBACK_FETCH_DATA_FLAG_NONE = 0x00000000,
} CF_CALLBACK_FETCH_DATA_FLAGS;

typedef enum RS_CF_CALLBACK_FETCH_PLACEHOLDERS_FLAGS {
    CF_CALLBACK_FETCH_PLACEHOLDERS_FLAG_NONE = 0x00000000,
} CF_CALLBACK_FETCH_PLACEHOLDERS_FLAGS;

typedef enum RS_CF_CALLBACK_DELETE_COMPLETION_FLAGS {
    CF_CALLBACK_DELETE_COMPLETION_FLAG_NONE = 0x00000000,
} CF_CALLBACK_DELETE_COMPLETION_FLAGS;

typedef enum RS_CF_CALLBACK_RENAME_COMPLETION_FLAGS {
    CF_CALLBACK_RENAME_COMPLETION_FLAG_NONE = 0x00000000,
} CF_CALLBACK_RENAME_COMPLETION_FLAGS;

typedef struct RS_CF_CALLBACK_PARAMETERS {
    ULONG ParamSize;
    union {
        struct {
            CF_CALLBACK_FETCH_DATA_FLAGS Flags;
            LARGE_INTEGER RequiredFileOffset;
            LARGE_INTEGER RequiredLength;
            LARGE_INTEGER OptionalFileOffset;
            LARGE_INTEGER OptionalLength;
            LARGE_INTEGER LastDehydrationTime;
            ULONG LastDehydrationReason;
        } FetchData;
        struct {
            CF_CALLBACK_FETCH_PLACEHOLDERS_FLAGS Flags;
            PCWSTR Pattern;
        } FetchPlaceholders;
        struct {
            CF_CALLBACK_DELETE_COMPLETION_FLAGS Flags;
        } DeleteCompletion;
        struct {
            CF_CALLBACK_RENAME_COMPLETION_FLAGS Flags;
            PCWSTR SourcePath;
        } RenameCompletion;
    };
} CF_CALLBACK_PARAMETERS;

typedef VOID (CALLBACK *CF_CALLBACK)(
    const CF_CALLBACK_INFO* CallbackInfo,
    const CF_CALLBACK_PARAMETERS* CallbackParameters);

typedef enum RS_CF_CALLBACK_TYPE {
    CF_CALLBACK_TYPE_FETCH_DATA = 0,
    CF_CALLBACK_TYPE_VALIDATE_DATA = 1,
    CF_CALLBACK_TYPE_CANCEL_FETCH_DATA = 2,
    CF_CALLBACK_TYPE_FETCH_PLACEHOLDERS = 3,
    CF_CALLBACK_TYPE_NOTIFY_FILE_OPEN_COMPLETION = 5,
    CF_CALLBACK_TYPE_NOTIFY_FILE_CLOSE_COMPLETION = 6,
    CF_CALLBACK_TYPE_NOTIFY_DELETE_COMPLETION = 10,
    CF_CALLBACK_TYPE_NOTIFY_RENAME_COMPLETION = 12,
    CF_CALLBACK_TYPE_NONE = 0xffffffff,
} CF_CALLBACK_TYPE;

typedef struct RS_CF_CALLBACK_REGISTRATION {
    CF_CALLBACK_TYPE Type;
    CF_CALLBACK Callback;
} CF_CALLBACK_REGISTRATION;

#define CF_CALLBACK_REGISTRATION_END {CF_CALLBACK_TYPE_NONE, NULL}

typedef enum RS_CF_CONNECT_FLAGS {
    CF_CONNECT_FLAG_NONE = 0x00000000,
    CF_CONNECT_FLAG_REQUIRE_PROCESS_INFO = 0x00000002,
    CF_CONNECT_FLAG_REQUIRE_FULL_FILE_PATH = 0x00000004,
} CF_CONNECT_FLAGS;

typedef enum RS_CF_OPERATION_TYPE {
    CF_OPERATION_TYPE_TRANSFER_DATA = 0,
    CF_OPERATION_TYPE_TRANSFER_PLACEHOLDERS = 4,
} CF_OPERATION_TYPE;

typedef struct RS_CF_SYNC_STATUS {
    ULONG StructSize;
    ULONG Code;
    ULONG DescriptionOffset;
    ULONG DescriptionLength;
    ULONG DeviceIdOffset;
    ULONG DeviceIdLength;
} CF_SYNC_STATUS;

typedef struct RS_CF_OPERATION_INFO {
    ULONG StructSize;
    CF_OPERATION_TYPE Type;
    CF_CONNECTION_KEY ConnectionKey;
    CF_TRANSFER_KEY TransferKey;
    const void* CorrelationVector;
    const CF_SYNC_STATUS* SyncStatus;
    CF_REQUEST_KEY RequestKey;
} CF_OPERATION_INFO;

typedef enum RS_CF_OPERATION_TRANSFER_DATA_FLAGS {
    CF_OPERATION_TRANSFER_DATA_FLAG_NONE = 0x00000000,
} CF_OPERATION_TRANSFER_DATA_FLAGS;

typedef enum RS_CF_OPERATION_TRANSFER_PLACEHOLDERS_FLAGS {
    CF_OPERATION_TRANSFER_PLACEHOLDERS_FLAG_NONE = 0x00000000,
    CF_OPERATION_TRANSFER_PLACEHOLDERS_FLAG_STOP_ON_ERROR = 0x00000001,
    CF_OPERATION_TRANSFER_PLACEHOLDERS_FLAG_DISABLE_ON_DEMAND_POPULATION = 0x00000002,
} CF_OPERATION_TRANSFER_PLACEHOLDERS_FLAGS;

typedef struct RS_CF_OPERATION_PARAMETERS {
    ULONG ParamSize;
    union {
        struct {
            CF_OPERATION_TRANSFER_DATA_FLAGS Flags;
            NTSTATUS CompletionStatus;
            LPCVOID Buffer;
            LARGE_INTEGER Offset;
            LARGE_INTEGER Length;
        } TransferData;
        struct {
            CF_OPERATION_TRANSFER_PLACEHOLDERS_FLAGS Flags;
            NTSTATUS CompletionStatus;
            LARGE_INTEGER PlaceholderTotalCount;
            CF_PLACEHOLDER_CREATE_INFO* PlaceholderArray;
            DWORD PlaceholderCount;
            DWORD EntriesProcessed;
        } TransferPlaceholders;
    };
} CF_OPERATION_PARAMETERS;

#define RS_SIZE_OF_OP_PARAM(member) ((ULONG)(FIELD_OFFSET(CF_OPERATION_PARAMETERS, member) + sizeof(((CF_OPERATION_PARAMETERS*)0)->member)))

typedef enum RS_CF_CREATE_FLAGS {
    CF_CREATE_FLAG_NONE = 0x00000000,
} CF_CREATE_FLAGS;

typedef enum RS_CF_IN_SYNC_STATE {
    CF_IN_SYNC_STATE_NOT_IN_SYNC = 0,
    CF_IN_SYNC_STATE_IN_SYNC = 1,
} CF_IN_SYNC_STATE;

typedef enum RS_CF_SET_IN_SYNC_FLAGS {
    CF_SET_IN_SYNC_FLAG_NONE = 0x00000000,
} CF_SET_IN_SYNC_FLAGS;

typedef long long rs_connection_key_t;

LPWSTR rs_utf8_to_wchar(const char* utf8);
void rs_free_wchar(LPWSTR wstr);
char* rs_wchar_to_utf8(LPCWSTR wstr);
void rs_free_utf8(char* str);

HRESULT rs_cf_register(LPCWSTR syncRootPath, LPCWSTR providerID, LPCWSTR displayName);
HRESULT rs_cf_deregister(LPCWSTR syncRootPath);
HRESULT rs_cf_connect(LPCWSTR localPath, rs_connection_key_t* outKey);
HRESULT rs_cf_disconnect(rs_connection_key_t key);
HRESULT rs_cf_create_placeholders(
    LPCWSTR localPath,
    CF_PLACEHOLDER_CREATE_INFO* items,
    DWORD count,
    DWORD* outCreated);
HRESULT rs_cf_set_sync_state(LPCWSTR localPath, int state);
HRESULT rs_cf_execute_transfer(
    uintptr_t callbackInfoPtr,
    LARGE_INTEGER offset,
    LARGE_INTEGER length,
    const BYTE* data);
HRESULT rs_cf_report_error(uintptr_t callbackInfoPtr, HRESULT providerError);
HRESULT rs_cf_ack_placeholders(uintptr_t callbackInfoPtr, HRESULT completionStatus);
HRESULT rs_cf_complete_placeholders(uintptr_t callbackInfoPtr, HRESULT completionStatus, DWORD flags);
HRESULT rs_cf_report_progress_cb(
    uintptr_t callbackInfoPtr,
    LARGE_INTEGER total,
    LARGE_INTEGER done);
LONGLONG rs_fetch_data_offset(const CF_CALLBACK_PARAMETERS* params);
LONGLONG rs_fetch_data_length(const CF_CALLBACK_PARAMETERS* params);
char* rs_rename_source_path(const CF_CALLBACK_PARAMETERS* params);

#endif
