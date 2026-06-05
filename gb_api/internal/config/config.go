package config

import (
	"encoding/hex"
	"fmt"
	"os"

	"gb-api/internal/logger"
)

// JWT signing keys, loaded from env vars with insecure development defaults.
// Set JWT_KEY and JWT_REFRESH_KEY in production to 64-char hex strings
// (32 bytes / 256 bits, the minimum for HS256).
var JwtKey = keyFromEnv("JWT_KEY", "your_secret_key_keep_it_safe")
var RefreshKey = keyFromEnv("JWT_REFRESH_KEY", "your_refresh_secret_keep_it_safe")

// keyFromEnv reads name from the environment and decodes its first 64 hex
// characters into a 32-byte key. If name is unset it falls back to the
// development default. A set-but-invalid value (too short or not hex) is fatal.
func keyFromEnv(name, fallback string) []byte {
	v := os.Getenv(name)
	if v == "" {
		logger.L.Warn(fmt.Sprintf("config: %s cannot be loaded", name))
		logger.L.Warn("config: Using fallback string")
		return []byte(fallback)
	}
	if len(v) < 64 {
		logger.L.Warn(fmt.Sprintf("config: %s must be at least 64 hex chars, got %d", name, len(v)))
		logger.L.Warn("config: Using fallback string")
		return []byte(fallback)
	}
	key, err := hex.DecodeString(v[:64])
	if err != nil {
		logger.L.Warn(fmt.Sprintf("config: %s is not a valid hex string: %v", name, err))
		logger.L.Warn("config: Using fallback string")
		return []byte(fallback)
	}
	logger.L.Info(fmt.Sprintf("config: %s loaded", name))
	return key
}
