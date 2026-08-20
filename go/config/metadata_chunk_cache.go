// Metadata chunk cache support protects pending content without importing the
// metadata package, which would otherwise create a config import cycle.
package config

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
)

const metadataChunkStoreDir = "metadata-chunks"

type metadataChunkProtectionManifest struct {
	Version      int
	Conservative bool
	Chunks       map[string]int64
}

type metadataChunkProtection struct {
	all     map[string]struct{}
	pending map[string]struct{}
}

func loadMetadataChunkProtection(cacheRoot string) metadataChunkProtection {
	protection := metadataChunkProtection{
		all:     map[string]struct{}{},
		pending: map[string]struct{}{},
	}
	root := filepath.Join(cacheRoot, metadataChunkStoreDir)
	entries, err := os.ReadDir(root)
	if err != nil {
		return protection
	}
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		namespaceRoot := filepath.Join(root, entry.Name())
		chunksRoot := filepath.Join(namespaceRoot, "chunks")
		manifestPath := filepath.Join(namespaceRoot, "protection.json")
		manifest, ok := readChunkProtectionManifest(manifestPath)
		if !ok {
			protection.protectTree(chunksRoot, true)
		} else {
			// The manifest is part of the protection protocol. Keep it through
			// ClearAll so a concurrent staging pass cannot lose its conservative
			// marker between cleanup scans.
			protection.all[filepath.Clean(manifestPath)] = struct{}{}
			if manifest.Conservative {
				protection.protectTree(chunksRoot, true)
			} else {
				for hash := range manifest.Chunks {
					if !validMetadataChunkHash(hash) {
						protection.protectTree(chunksRoot, true)
						break
					}
					path := filepath.Join(chunksRoot, hash[:2], hash)
					clean := filepath.Clean(path)
					protection.all[clean] = struct{}{}
					protection.pending[clean] = struct{}{}
				}
			}
		}
		// An upload splice is live data too. It is not counted as pending
		// content, but cleanup must never delete it during an active upload.
		protection.protectTree(filepath.Join(namespaceRoot, "tmp"), false)
	}
	return protection
}

func readChunkProtectionManifest(path string) (metadataChunkProtectionManifest, bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return metadataChunkProtectionManifest{}, false
	}
	var manifest metadataChunkProtectionManifest
	if err := json.Unmarshal(data, &manifest); err != nil || manifest.Version != 1 || manifest.Chunks == nil {
		return metadataChunkProtectionManifest{}, false
	}
	return manifest, true
}

func (p metadataChunkProtection) protectTree(root string, pending bool) {
	_ = filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil || info == nil || info.IsDir() {
			return nil
		}
		clean := filepath.Clean(path)
		p.all[clean] = struct{}{}
		if pending {
			p.pending[clean] = struct{}{}
		}
		return nil
	})
}

func (p metadataChunkProtection) protected(path string) bool {
	_, ok := p.all[filepath.Clean(path)]
	return ok
}

func (p metadataChunkProtection) isPending(path string) bool {
	_, ok := p.pending[filepath.Clean(path)]
	return ok
}

func validMetadataChunkHash(hash string) bool {
	if len(hash) != sha256.Size*2 {
		return false
	}
	_, err := hex.DecodeString(hash)
	return err == nil
}
