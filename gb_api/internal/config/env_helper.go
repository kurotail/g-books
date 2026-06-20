package config

import (
	"encoding/hex"
	"fmt"
	"gb-api/internal/logger"
	"os"
	"strconv"
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
