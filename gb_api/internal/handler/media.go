package handler

import (
	"io"
	"net/http"

	"gb-api/internal/service"
)

type MediaHandler struct {
	svc *service.MediaSvc
}

func NewMediaHandler(s *service.MediaSvc) *MediaHandler {
	return &MediaHandler{svc: s}
}

// UploadImage accepts a multipart/form-data request with a "file" field holding
// an image, stores it, and returns the URL it can be fetched from.
func (h *MediaHandler) UploadImage(w http.ResponseWriter, r *http.Request) {
	h.upload(w, r, h.svc.SaveImage, h.svc.ImageMaxBytes())
}

// UploadAudio accepts a multipart/form-data request with a "file" field holding
// an audio file, stores it, and returns the URL it can be fetched from.
func (h *MediaHandler) UploadAudio(w http.ResponseWriter, r *http.Request) {
	h.upload(w, r, h.svc.SaveAudio, h.svc.AudioMaxBytes())
}

type saveFunc func(accessToken string, data []byte, filename string) ([]byte, int, error)

func (h *MediaHandler) upload(w http.ResponseWriter, r *http.Request, save saveFunc, maxBytes int64) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	// Bound the body to the cap (plus headroom for multipart framing) so an
	// oversized upload is rejected without being fully buffered.
	r.Body = http.MaxBytesReader(w, r.Body, maxBytes+(1<<20))
	file, hdr, err := r.FormFile("file")
	if err != nil {
		http.Error(w, "缺少 file 檔案欄位或檔案超過大小上限", http.StatusBadRequest)
		return
	}
	defer file.Close()

	data, err := io.ReadAll(file)
	if err != nil {
		http.Error(w, "檔案讀取失敗或超過大小上限", http.StatusBadRequest)
		return
	}
	out, status, err := save(token, data, hdr.Filename)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSONStatus(w, status, out)
}
