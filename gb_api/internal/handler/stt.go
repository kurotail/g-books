package handler

import (
	"encoding/json"
	"net/http"

	"gb-api/internal/model"
	"gb-api/internal/service"
)

type STTHandler struct {
	svc *service.STTSvc
}

func NewSTTHandler(s *service.STTSvc) *STTHandler {
	return &STTHandler{svc: s}
}

// Transcribe accepts a JSON body with a base64-encoded WAV recording and returns the
// recognized text. Teacher/admin only.
func (h *STTHandler) Transcribe(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.TranscribeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	if req.AudioB64 == "" {
		http.Error(w, "缺少 audio_b64", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.Transcribe(token, req.AudioB64)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}
