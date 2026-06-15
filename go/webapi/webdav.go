// WebDAV service caches per-bucket handlers so browser clients can reuse sessions.
package webapi

import (
	"net/http"
	"sync"

	storageconfig "remote-storage/go/config"
	bucketmount "remote-storage/go/mount"
)

type webDAVService struct {
	mu       sync.Mutex
	handlers map[string]*bucketmount.BucketWebDAVHandler
}

func newWebDAVService() *webDAVService {
	return &webDAVService{handlers: map[string]*bucketmount.BucketWebDAVHandler{}}
}

func (s *webDAVService) HandlerFor(
	config storageconfig.RemoteStorageConfig,
	bucket string,
	prefix string,
) (http.Handler, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	handler, ok := s.handlers[bucket]
	if ok {
		return handler, nil
	}
	nextHandler, err := bucketmount.NewBucketWebDAVHandler(config, bucket, prefix)
	if err != nil {
		return nil, err
	}
	s.handlers[bucket] = nextHandler
	return nextHandler, nil
}

func (s *webDAVService) Reset() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	var firstErr error
	for bucket, handler := range s.handlers {
		if err := handler.Close(); err != nil && firstErr == nil {
			firstErr = err
		}
		delete(s.handlers, bucket)
	}
	return firstErr
}
