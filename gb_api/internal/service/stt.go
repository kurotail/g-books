package service

import (
	"encoding/json"
	"fmt"
	"net/http"

	"gb-api/internal/model"
	"gb-api/internal/repo"
)

type STTSvc struct {
	stt   repo.STTRepo
	users repo.UserRepo
}

func NewSTTSvc(stt repo.STTRepo, users repo.UserRepo) *STTSvc {
	return &STTSvc{stt: stt, users: users}
}

// Transcribe runs a base64-encoded WAV recording through the STT service and returns
// the recognized text. Only teachers/admins may call it.
func (s *STTSvc) Transcribe(accessToken, audioB64 string) ([]byte, int, error) {
	if status, err := requireTeacher(s.users, accessToken); err != nil {
		return nil, status, err
	}
	if audioB64 == "" {
		return nil, http.StatusBadRequest, fmt.Errorf("缺少 audio_b64")
	}
	text, err := s.stt.Transcribe(audioB64) // repo validates the base64 itself
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	out, err := json.Marshal(model.TranscribeResponse{Text: text})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return out, http.StatusOK, nil
}
