package config

import (
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

// STTBaseURL is the address of the Taigi speech-to-text service. The API runs in a
// container, so the default reaches a service on the Docker host via host.docker.internal.
var STTBaseURL = stringFromEnv("STT_BASE_URL", "http://host.docker.internal:8964")
