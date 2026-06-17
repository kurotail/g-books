package config

import (
	"context"
	"gb-api/internal/repo"
	"time"
)

// Set JWT_KEY and JWT_REFRESH_KEY in production to 64-char hex strings
var JwtKey = keyFromEnv("JWT_KEY", "your_secret_key_keep_it_safe")
var RefreshKey = keyFromEnv("JWT_REFRESH_KEY", "your_refresh_secret_keep_it_safe")

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

type closeFunction func()

func Init() (closeFunction, error) {
	// Connect to Postgres, apply the schema, and seed the admin account
	initCtx, cancelInit := context.WithTimeout(context.Background(), 60*time.Second)
	if err := repo.Init(initCtx, DatabaseURL, AdminUsername, AdminPassword); err != nil {
		cancelInit()
		return func() {}, err
	}
	cancelInit()

	return repo.Close, nil
}
