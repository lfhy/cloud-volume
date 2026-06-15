// WebDAV access helpers detect per-directory write permissions when advertised.
package storage

import (
	"context"
	"encoding/xml"
	"fmt"
	"log"
	"net/http"
	"strings"
)

var webDAVReadOnlyOptionsMethods = map[string]struct{}{
	"GET":      {},
	"HEAD":     {},
	"OPTIONS":  {},
	"PROPFIND": {},
	"REPORT":   {},
	"TRACE":    {},
}

var webDAVMutatingOptionsMethods = map[string]struct{}{
	"COPY":      {},
	"DELETE":    {},
	"LOCK":      {},
	"MKCOL":     {},
	"MOVE":      {},
	"PATCH":     {},
	"POST":      {},
	"PROPPATCH": {},
	"PUT":       {},
	"UNLOCK":    {},
}

func (b webDAVBackend) DirectoryAccess(
	ctx context.Context,
	bucket, prefix string,
) (DirectoryAccess, error) {
	dirKey := webDAVDirectoryKey(prefix)
	log.Printf("[webdav/access] start bucket=%q prefix=%q dir_key=%q", bucket, prefix, dirKey)
	access, err := b.directoryAccessFromPropfind(ctx, bucket, prefix, dirKey)
	if err == nil && access.Known {
		log.Printf(
			"[webdav/access] done bucket=%q prefix=%q source=%q writable=%t known=%t reason=%q",
			bucket,
			prefix,
			"propfind",
			access.Writable,
			access.Known,
			access.Reason,
		)
		return access, nil
	}
	if err != nil {
		log.Printf("[webdav/access] propfind-error bucket=%q prefix=%q error=%v", bucket, prefix, err)
	} else {
		log.Printf(
			"[webdav/access] propfind-unknown bucket=%q prefix=%q writable=%t known=%t",
			bucket,
			prefix,
			access.Writable,
			access.Known,
		)
	}
	access, err = b.directoryAccessFromOptions(ctx, bucket, prefix, dirKey)
	if err != nil {
		log.Printf("[webdav/access] options-error bucket=%q prefix=%q error=%v", bucket, prefix, err)
		return DirectoryAccess{}, err
	}
	log.Printf(
		"[webdav/access] done bucket=%q prefix=%q source=%q writable=%t known=%t reason=%q",
		bucket,
		prefix,
		"options",
		access.Writable,
		access.Known,
		access.Reason,
	)
	return access, nil
}

func (b webDAVBackend) ensureWritableDirectory(ctx context.Context, bucket, prefix string) error {
	access, err := b.DirectoryAccess(ctx, bucket, cleanParentDirectory(prefix))
	if err != nil {
		return err
	}
	if access.Known && !access.Writable {
		if access.Reason != "" {
			return fmt.Errorf("%s", access.Reason)
		}
		return fmt.Errorf("当前 WebDAV 目录为只读，无法写入")
	}
	return nil
}

func cleanParentDirectory(value string) string {
	clean := cleanRemotePath(value)
	if clean == "." {
		return ""
	}
	return clean
}

func (b webDAVBackend) directoryAccessFromPropfind(
	ctx context.Context,
	bucket string,
	prefix string,
	dirKey string,
) (DirectoryAccess, error) {
	req, err := b.request(ctx, "PROPFIND", dirKey, strings.NewReader(webDAVPrivilegePropfindBody))
	if err != nil {
		return DirectoryAccess{}, err
	}
	req.Header.Set("Depth", "0")
	req.Header.Set("Content-Type", `application/xml; charset="utf-8"`)
	resp, err := b.client.Do(req)
	if err != nil {
		return DirectoryAccess{}, err
	}
	defer resp.Body.Close()
	log.Printf(
		"[webdav/access] propfind-response bucket=%q prefix=%q dir_key=%q status=%q",
		bucket,
		prefix,
		dirKey,
		resp.Status,
	)
	if resp.StatusCode >= 300 {
		return DirectoryAccess{}, fmt.Errorf("webdav propfind: %s", resp.Status)
	}
	var multi webDAVPrivilegeMultistatus
	if err := xml.NewDecoder(resp.Body).Decode(&multi); err != nil {
		return DirectoryAccess{}, err
	}
	for responseIndex, response := range multi.Responses {
		for propstatIndex, propstat := range response.Propstat {
			if !propstat.statusOK() || len(propstat.Prop.Privileges) == 0 {
				log.Printf(
					"[webdav/access] propfind-skip bucket=%q prefix=%q response=%d propstat=%d status=%q privilege_count=%d",
					bucket,
					prefix,
					responseIndex,
					propstatIndex,
					propstat.Status,
					len(propstat.Prop.Privileges),
				)
				continue
			}
			names := webDAVPrivilegeNames(propstat.Prop.Privileges)
			access := accessFromPrivileges(propstat.Prop.Privileges)
			log.Printf(
				"[webdav/access] privileges bucket=%q prefix=%q names=%q writable=%t known=%t reason=%q",
				bucket,
				prefix,
				names,
				access.Writable,
				access.Known,
				access.Reason,
			)
			return access, nil
		}
	}
	log.Printf("[webdav/access] propfind-no-privileges bucket=%q prefix=%q", bucket, prefix)
	return DirectoryAccess{Writable: true, Known: false}, nil
}

func (b webDAVBackend) directoryAccessFromOptions(
	ctx context.Context,
	bucket string,
	prefix string,
	dirKey string,
) (DirectoryAccess, error) {
	req, err := b.request(ctx, http.MethodOptions, dirKey, nil)
	if err != nil {
		return DirectoryAccess{}, err
	}
	resp, err := b.client.Do(req)
	if err != nil {
		return DirectoryAccess{}, err
	}
	defer resp.Body.Close()
	allow := strings.ToUpper(resp.Header.Get("Allow"))
	log.Printf(
		"[webdav/access] options-response bucket=%q prefix=%q dir_key=%q status=%q allow=%q",
		bucket,
		prefix,
		dirKey,
		resp.Status,
		allow,
	)
	if resp.StatusCode == http.StatusForbidden || resp.StatusCode == http.StatusUnauthorized {
		return DirectoryAccess{Writable: false, Known: true, Reason: "当前 WebDAV 目录为只读，无法写入"}, nil
	}
	if resp.StatusCode >= 300 {
		return DirectoryAccess{Writable: true, Known: false}, nil
	}
	if allow == "" {
		return DirectoryAccess{Writable: true, Known: false}, nil
	}
	methods := parseAllowMethods(allow)
	if hasAnyMethod(methods, "PUT", "MKCOL") {
		return DirectoryAccess{Writable: true, Known: true}, nil
	}
	if hasMutatingOptionsMethod(methods) {
		return DirectoryAccess{Writable: true, Known: false}, nil
	}
	if isReadOnlyOptionsMethodSet(methods) {
		return DirectoryAccess{Writable: false, Known: true, Reason: "当前 WebDAV 目录为只读，无法写入"}, nil
	}
	return DirectoryAccess{Writable: true, Known: false}, nil
}

func parseAllowMethods(allow string) map[string]struct{} {
	methods := make(map[string]struct{})
	for _, part := range strings.Split(allow, ",") {
		method := strings.ToUpper(strings.TrimSpace(part))
		if method == "" {
			continue
		}
		methods[method] = struct{}{}
	}
	return methods
}

func hasAnyMethod(methods map[string]struct{}, names ...string) bool {
	for _, name := range names {
		if _, ok := methods[name]; ok {
			return true
		}
	}
	return false
}

func hasMutatingOptionsMethod(methods map[string]struct{}) bool {
	for method := range methods {
		if _, ok := webDAVMutatingOptionsMethods[method]; ok {
			return true
		}
	}
	return false
}

func isReadOnlyOptionsMethodSet(methods map[string]struct{}) bool {
	if len(methods) == 0 {
		return false
	}
	for method := range methods {
		if _, ok := webDAVReadOnlyOptionsMethods[method]; !ok {
			return false
		}
	}
	return true
}

func webDAVDirectoryKey(prefix string) string {
	clean := cleanRemotePath(prefix)
	if clean == "" {
		return ""
	}
	return clean + "/"
}

func accessFromPrivileges(privileges []webDAVPrivilege) DirectoryAccess {
	var readable bool
	var writable bool
	for _, privilege := range privileges {
		for _, name := range privilege.Names {
			local := strings.ToLower(name.Local)
			if local == "read" {
				readable = true
			}
			if local == "write" || local == "write-content" || local == "bind" ||
				local == "unbind" || local == "all" {
				writable = true
			}
		}
	}
	if writable {
		return DirectoryAccess{Writable: true, Known: true}
	}
	if readable {
		return DirectoryAccess{Writable: false, Known: true, Reason: "当前 WebDAV 目录为只读，无法写入"}
	}
	return DirectoryAccess{Writable: true, Known: false}
}

func webDAVPrivilegeNames(privileges []webDAVPrivilege) []string {
	names := make([]string, 0, len(privileges))
	for _, privilege := range privileges {
		for _, name := range privilege.Names {
			names = append(names, strings.ToLower(name.Local))
		}
	}
	return names
}

const webDAVPrivilegePropfindBody = `<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:current-user-privilege-set/>
  </D:prop>
</D:propfind>`

type webDAVPrivilegeMultistatus struct {
	Responses []webDAVPrivilegeResponse `xml:"response"`
}

type webDAVPrivilegeResponse struct {
	Propstat []webDAVPrivilegePropstat `xml:"propstat"`
}

type webDAVPrivilegePropstat struct {
	Status string              `xml:"status"`
	Prop   webDAVPrivilegeProp `xml:"prop"`
}

func (p webDAVPrivilegePropstat) statusOK() bool {
	return p.Status == "" || strings.Contains(p.Status, " 200 ")
}

type webDAVPrivilegeProp struct {
	Privileges []webDAVPrivilege `xml:"current-user-privilege-set>privilege"`
}

type webDAVPrivilege struct {
	Names []xml.Name `xml:",any"`
}
