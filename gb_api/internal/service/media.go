package service

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"gb-api/internal/model"
)

// mediaKind describes an upload category: which subdirectory it is stored in,
// the URL prefix it is served at, its size cap, and the formats it accepts.
type mediaKind struct {
	subdir   string
	urlBase  string
	maxBytes int64
	types    map[string]string // sniffed MIME type -> on-disk extension
	exts     map[string]string // accepted extension -> normalized extension
}

// resolveExt picks the on-disk extension from the sniffed content type, falling
// back to the client filename extension only when the content is otherwise
// unrecognized (common for tag-less mp3, which sniffs as octet-stream).
func (k mediaKind) resolveExt(data []byte, filename string) (string, bool) {
	ct := http.DetectContentType(data)
	if ext, ok := k.types[ct]; ok {
		return ext, true
	}
	if ct == "application/octet-stream" {
		if ext, ok := k.exts[strings.ToLower(filepath.Ext(filename))]; ok {
			return ext, true
		}
	}
	return "", false
}

type MediaSvc struct {
	dir   string
	image mediaKind
	audio mediaKind
}

func NewMediaSvc(dir string, maxImageMB, maxAudioMB int) *MediaSvc {
	return &MediaSvc{
		dir: dir,
		image: mediaKind{
			subdir:   "images",
			urlBase:  "/images/",
			maxBytes: int64(maxImageMB) << 20,
			types: map[string]string{
				"image/jpeg": ".jpg",
				"image/png":  ".png",
				"image/gif":  ".gif",
				"image/webp": ".webp",
			},
			exts: map[string]string{
				".jpg": ".jpg", ".jpeg": ".jpg", ".png": ".png", ".gif": ".gif", ".webp": ".webp",
			},
		},
		audio: mediaKind{
			subdir:   "audio",
			urlBase:  "/audio/",
			maxBytes: int64(maxAudioMB) << 20,
			types: map[string]string{
				"audio/mpeg": ".mp3",
				"audio/wave": ".wav",
				"audio/ogg":  ".ogg",
				"audio/aiff": ".aiff",
			},
			exts: map[string]string{
				".mp3": ".mp3", ".wav": ".wav", ".ogg": ".ogg",
				".m4a": ".m4a", ".aac": ".aac", ".flac": ".flac", ".aiff": ".aiff",
			},
		},
	}
}

// ImageMaxBytes / AudioMaxBytes expose the configured caps so the handler can
// bound the request body before reading it.
func (s *MediaSvc) ImageMaxBytes() int64 { return s.image.maxBytes }
func (s *MediaSvc) AudioMaxBytes() int64 { return s.audio.maxBytes }

// SaveImage stores an uploaded image and returns its public URL.
func (s *MediaSvc) SaveImage(accessToken string, data []byte, filename string) ([]byte, int, error) {
	return s.save(s.image, accessToken, data, filename)
}

// SaveAudio stores an uploaded audio file and returns its public URL.
func (s *MediaSvc) SaveAudio(accessToken string, data []byte, filename string) ([]byte, int, error) {
	return s.save(s.audio, accessToken, data, filename)
}

func (s *MediaSvc) save(k mediaKind, accessToken string, data []byte, filename string) ([]byte, int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return nil, http.StatusUnauthorized, err
	}
	if len(data) == 0 {
		return nil, http.StatusBadRequest, fmt.Errorf("檔案為空")
	}
	if int64(len(data)) > k.maxBytes {
		return nil, http.StatusRequestEntityTooLarge, fmt.Errorf("檔案超過大小上限 (%d MiB)", k.maxBytes>>20)
	}
	ext, ok := k.resolveExt(data, filename)
	if !ok {
		return nil, http.StatusUnsupportedMediaType, fmt.Errorf("不支援的檔案格式")
	}
	name, err := randomName()
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	name += ext

	dst := filepath.Join(s.dir, k.subdir)
	if err := os.MkdirAll(dst, 0o755); err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if err := os.WriteFile(filepath.Join(dst, name), data, 0o644); err != nil {
		return nil, http.StatusInternalServerError, err
	}
	out, err := json.Marshal(model.MediaUploadResponse{
		Filename: name,
		URL:      k.urlBase + name,
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return out, http.StatusCreated, nil
}

func randomName() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
