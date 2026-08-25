// FTP backend connects to a classic FTP server using jlaffaye/ftp as the client.
// It exposes the remote tree as a single virtual bucket, mirroring the WebDAV
// backend contract so the rest of the app does not need FTP-specific code.
package storage

import (
	"context"
	"fmt"
	"net"
	"strconv"
	"strings"
	"time"

	ftpclient "github.com/jlaffaye/ftp"

	storageconfig "remote-storage/go/config"
)

// ftpBackend implements Backend over a classic FTP control+data connection.
type ftpBackend struct {
	cfg storageconfig.RemoteStorageConfig
}

// newFTPBackend constructs an FTP backend from the normalized config.
func newFTPBackend(cfg storageconfig.RemoteStorageConfig) Backend {
	return ftpBackend{cfg: cfg}
}

// ftpConnect dials the configured FTP endpoint and authenticates.
// The returned connection must be closed by the caller.
func (b ftpBackend) ftpConnect(ctx context.Context) (*ftpclient.ServerConn, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	host := b.dialHost()
	timeout := 30 * time.Second
	opts := []ftpclient.DialOption{ftpclient.DialWithTimeout(timeout), ftpclient.DialWithContext(ctx)}
	conn, err := ftpclient.Dial(host, opts...)
	if err != nil {
		return nil, fmt.Errorf("ftp dial %s: %w", host, err)
	}
	user, pass := b.ftpCredentials()
	if err := conn.Login(user, pass); err != nil {
		_ = conn.Quit()
		return nil, fmt.Errorf("ftp login: %w", err)
	}
	return conn, nil
}

// ftpHostPort extracts host:port from an endpoint URL or bare address.
// If no port is present the FTP default 21 is assumed.
func ftpHostPort(endpoint string) string {
	return hostPortFromEndpoint(endpoint, 21)
}

// ftpCredentials returns (username, password) for the FTP connection,
// applying anonymous login conventions when FTPAnonymous is set.
func (b ftpBackend) ftpCredentials() (string, string) {
	if b.cfg.FTPAnonymous {
		user := b.cfg.FTPUsername
		if user == "" {
			user = "anonymous"
		}
		pass := b.cfg.FTPPassword
		if pass == "" {
			pass = "anonymous@"
		}
		return user, pass
	}
	return b.cfg.FTPUsername, b.cfg.FTPPassword
}

// ftpHostFromConfig resolves the host:port to dial, honoring an explicit FTPPort override.
func (b ftpBackend) dialHost() string {
	host := hostFromEndpoint(b.cfg.Endpoint)
	if b.cfg.FTPPort > 0 {
		return net.JoinHostPort(host, strconv.Itoa(b.cfg.FTPPort))
	}
	return hostPortFromEndpoint(b.cfg.Endpoint, 21)
}

// ftpBucketLabel returns the display name for the single virtual bucket.
func ftpBucketLabel(cfg storageconfig.RemoteStorageConfig) string {
	label := strings.TrimSpace(cfg.MappedBucketLabel())
	if label != "" {
		return label
	}
	return "FTP"
}

func (b ftpBackend) bucketConfig(bucket string) storageconfig.RemoteStorageConfig {
	return b.cfg.WithBucketSettingsApplied(bucket)
}

func (b ftpBackend) ensureBucketWritable(bucket string) error {
	if b.bucketConfig(bucket).BucketSettingsFor(bucket).ReadOnly {
		return fmt.Errorf("当前存储桶已配置为只读，无法写入")
	}
	return nil
}

// ftpRemotePath converts a view-relative key to an absolute FTP server path.
// FTP servers expect Unix-style paths starting with /.
func ftpRemotePath(key string) string {
	clean := strings.Trim(strings.TrimSpace(key), "/")
	if clean == "" {
		return "/"
	}
	return "/" + clean
}

// ftpBucketQuota implements BucketQuotaProvider for FTP.
// FTP has no standard quota protocol; we try a best-effort STAT probe.
func (b ftpBackend) BucketQuota(ctx context.Context, bucketName string) (BucketInfo, error) {
	bucket := BucketInfo{Name: bucketName}
	if !b.supportsQuota() {
		return bucket, nil
	}
	total, used, known, err := b.ftpQuota(ctx)
	if err != nil {
		return bucket, err
	}
	if known {
		bucket.QuotaBytes = total
		bucket.UsedBytes = used
		bucket.QuotaKnown = true
	}
	return bucket, nil
}

func (b ftpBackend) ListBuckets(context.Context) ([]BucketInfo, error) {
	return []BucketInfo{{Name: ftpBucketLabel(b.cfg)}}, nil
}

// ftpEntryFromInfo converts an ftp entry into the shared ObjectInfo shape.
func ftpEntryFromInfo(parentDir string, entry *ftpclient.Entry) ObjectInfo {
	name := strings.TrimSpace(entry.Name)
	if name == "" {
		return ObjectInfo{}
	}
	key := strings.TrimPrefix(strings.TrimRight(parentDir, "/")+"/"+name, "/")
	isDir := entry.Type == ftpclient.EntryTypeFolder
	if isDir && !strings.HasSuffix(key, "/") {
		key += "/"
	}
	return ObjectInfo{
		Key:          key,
		Size:         int64(entry.Size),
		LastModified: entry.Time.In(time.Local).Format("2006-01-02 15:04:05"),
		IsDir:        isDir,
	}
}
