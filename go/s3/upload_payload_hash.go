// Payload hash helpers keep tracked whole-object uploads compatible with SigV4.
package s3

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws/signer/v4"
	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/smithy-go/middleware"
)

// precomputeFilePayloadHash lets the signer use a raw-file digest without
// reading the progress-wrapped body before the HTTP request is sent.
func precomputeFilePayloadHash(ctx context.Context, file *os.File) (func(*awss3.Options), error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return nil, fmt.Errorf("seek local upload to start: %w", err)
	}

	digest := sha256.New()
	if _, err := io.Copy(digest, file); err != nil {
		return nil, fmt.Errorf("hash local upload: %w", err)
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return nil, fmt.Errorf("rewind local upload after hashing: %w", err)
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	return precomputedPayloadHashOption(hex.EncodeToString(digest.Sum(nil))), nil
}

func precomputedPayloadHashOption(payloadHash string) func(*awss3.Options) {
	return func(options *awss3.Options) {
		options.APIOptions = append(options.APIOptions, func(stack *middleware.Stack) error {
			return stack.Finalize.Insert(
				&precomputedPayloadHashMiddleware{payloadHash: payloadHash},
				"ComputePayloadHash",
				middleware.Before,
			)
		})
	}
}

type precomputedPayloadHashMiddleware struct {
	payloadHash string
}

func (*precomputedPayloadHashMiddleware) ID() string {
	return "PrecomputedFilePayloadHash"
}

func (m *precomputedPayloadHashMiddleware) HandleFinalize(
	ctx context.Context,
	in middleware.FinalizeInput,
	next middleware.FinalizeHandler,
) (middleware.FinalizeOutput, middleware.Metadata, error) {
	return next.HandleFinalize(v4.SetPayloadHash(ctx, m.payloadHash), in)
}
