package config

import (
	"encoding/hex"
	"fmt"
	"os"
	"strconv"
	"time"

	"gb-api/internal/logger"
)

// Set JWT_KEY and JWT_REFRESH_KEY in production to 64-char hex strings
var JwtKey = keyFromEnv("JWT_KEY", "your_secret_key_keep_it_safe")
var RefreshKey = keyFromEnv("JWT_REFRESH_KEY", "your_refresh_secret_keep_it_safe")

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

const (
	AccessTokenTTL  = 15 * time.Minute
	RefreshTokenTTL = 7 * 24 * time.Hour
)

// UploadDir is where uploaded media are written; shared with nginx, which serves
// the files back at /images/ and /audio/.
var UploadDir = stringFromEnv("UPLOAD_DIR", "/srv/uploads")

// Per-category upload size caps, in MiB. Configurable via env.
var (
	MaxImageMB = intFromEnv("MAX_IMAGE_MB", 10)
	MaxAudioMB = intFromEnv("MAX_AUDIO_MB", 25)
)

func stringFromEnv(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}

func intFromEnv(name string, fallback int) int {
	v := os.Getenv(name)
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil || n <= 0 {
		logger.L.Warn(fmt.Sprintf("config: %s must be a positive integer, using fallback %d", name, fallback))
		return fallback
	}
	return n
}
