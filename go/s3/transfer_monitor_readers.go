// Cancellation-aware readers feed byte progress into the transfer monitor.
package s3

import (
	"context"
	"io"
)

type countingReader struct {
	reader io.Reader
	onRead func(int)
}

func (r *countingReader) Read(p []byte) (int, error) {
	n, err := r.reader.Read(p)
	if n > 0 && r.onRead != nil {
		r.onRead(n)
	}
	return n, err
}

type contextReader struct {
	ctx    context.Context
	reader io.Reader
	onRead func(int)
}

func (r *contextReader) Read(p []byte) (int, error) {
	select {
	case <-r.ctx.Done():
		return 0, r.ctx.Err()
	default:
	}
	n, err := r.reader.Read(p)
	if n > 0 && r.onRead != nil {
		r.onRead(n)
	}
	if err != nil {
		return n, err
	}
	select {
	case <-r.ctx.Done():
		return n, r.ctx.Err()
	default:
		return n, nil
	}
}

type contextReadSeeker struct {
	ctx    context.Context
	reader io.ReadSeeker
	onRead func(int)
}

func (r *contextReadSeeker) Read(p []byte) (int, error) {
	select {
	case <-r.ctx.Done():
		return 0, r.ctx.Err()
	default:
	}
	n, err := r.reader.Read(p)
	if n > 0 && r.onRead != nil {
		r.onRead(n)
	}
	if err != nil {
		return n, err
	}
	select {
	case <-r.ctx.Done():
		return n, r.ctx.Err()
	default:
		return n, nil
	}
}

func (r *contextReadSeeker) Seek(offset int64, whence int) (int64, error) {
	select {
	case <-r.ctx.Done():
		return 0, r.ctx.Err()
	default:
		return r.reader.Seek(offset, whence)
	}
}
