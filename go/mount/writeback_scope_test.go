// Writeback scope tests keep persisted uploads bound to the actual provider account.
package mount

import (
	"testing"

	storageconfig "remote-storage/go/config"
)

func TestWritebackScopeUsesProviderSpecificPrincipal(t *testing.T) {
	tests := []struct {
		name   string
		config storageconfig.RemoteStorageConfig
		change func(*storageconfig.RemoteStorageConfig)
	}{
		{
			name: "webdav username",
			config: storageconfig.RemoteStorageConfig{
				ProfileID: "profile", StorageType: storageconfig.StorageTypeWebDAV,
				Endpoint: "https://dav.example", Bucket: "bucket", WebDAVUsername: "alice",
			},
			change: func(config *storageconfig.RemoteStorageConfig) { config.WebDAVUsername = "bob" },
		},
		{
			name: "ftp username",
			config: storageconfig.RemoteStorageConfig{
				ProfileID: "profile", StorageType: storageconfig.StorageTypeFTP,
				Endpoint: "ftp.example", Bucket: "bucket", FTPUsername: "alice", FTPPort: 21,
			},
			change: func(config *storageconfig.RemoteStorageConfig) { config.FTPUsername = "bob" },
		},
		{
			name: "sftp port",
			config: storageconfig.RemoteStorageConfig{
				ProfileID: "profile", StorageType: storageconfig.StorageTypeSFTP,
				Endpoint: "sftp.example", Bucket: "bucket", FTPUsername: "alice", FTPPort: 22,
			},
			change: func(config *storageconfig.RemoteStorageConfig) { config.FTPPort = 2222 },
		},
		{
			name: "s3 access key",
			config: storageconfig.RemoteStorageConfig{
				ProfileID: "profile", StorageType: storageconfig.StorageTypeS3,
				Endpoint: "https://s3.example", Bucket: "bucket", AccessKeyID: "access-a",
			},
			change: func(config *storageconfig.RemoteStorageConfig) { config.AccessKeyID = "access-b" },
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			changed := test.config
			test.change(&changed)
			if writebackScope(test.config, "bucket") == writebackScope(changed, "bucket") {
				t.Fatalf("scope did not change after %s update", test.name)
			}
		})
	}
}

func TestWritebackScopeIgnoresBaiduAccessTokenRotation(t *testing.T) {
	config := storageconfig.RemoteStorageConfig{
		ProfileID:       "profile",
		StorageType:     storageconfig.StorageTypeBaiduPan,
		Endpoint:        "https://pan.baidu.com",
		Bucket:          "我的百度网盘",
		AccessKeyID:     "access-before",
		SecretAccessKey: "stable-refresh-token",
	}
	rotated := config
	rotated.AccessKeyID = "access-after"
	if writebackScope(config, config.Bucket) != writebackScope(rotated, rotated.Bucket) {
		t.Fatal("Baidu access-token refresh changed the writeback scope")
	}
	rotated.SecretAccessKey = "different-refresh-token"
	if writebackScope(config, config.Bucket) == writebackScope(rotated, rotated.Bucket) {
		t.Fatal("different Baidu refresh token reused the writeback scope")
	}
}
