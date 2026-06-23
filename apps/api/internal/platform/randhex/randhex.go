// Package randhex generates cryptographically-random hex strings used for
// unguessable tokens and object keys across features.
package randhex

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
)

// String returns a hex-encoded string of n random bytes (so 2*n hex chars).
func String(n int) (string, error) {
	bytes := make([]byte, n)
	if _, err := rand.Read(bytes); err != nil {
		return "", fmt.Errorf("generate random bytes: %w", err)
	}
	return hex.EncodeToString(bytes), nil
}
