package mount

import "context"

// webDAVRequestMethodKey marks the HTTP method while x/net/webdav calls the
// filesystem. This lets protocol-only LOCK resource creation stay out of the
// content journal without changing normal PUT semantics.
type webDAVRequestMethodKey struct{}

func webDAVRequestMethod(ctx context.Context) string {
	if ctx == nil {
		return ""
	}
	method, _ := ctx.Value(webDAVRequestMethodKey{}).(string)
	return method
}
