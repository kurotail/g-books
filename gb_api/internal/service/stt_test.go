package service

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"testing"

	"gb-api/internal/model"
	"gb-api/internal/repo/mock"
)

func newSTTSvc(role uint) *STTSvc {
	users := &mock.AuthRepo{Roles: map[string]uint{"u": role}}
	stt := &mock.STTRepo{Transcript: "hello world"}
	return NewSTTSvc(stt, users)
}

func TestSTTSvc_Transcribe_TeacherSucceeds(t *testing.T) {
	s := newSTTSvc(model.RoleTeacher)
	b64 := base64.StdEncoding.EncodeToString([]byte("RIFF....WAVE fake audio"))

	data, status, err := s.Transcribe(accessTokenFor(t, "u"), b64)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var resp model.TranscribeResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid response JSON: %v", err)
	}
	if resp.Text != "hello world" {
		t.Errorf("expected transcript %q, got %q", "hello world", resp.Text)
	}
}

func TestSTTSvc_Transcribe_StudentForbidden(t *testing.T) {
	s := newSTTSvc(model.RoleStudent)
	b64 := base64.StdEncoding.EncodeToString([]byte("RIFF....WAVE fake audio"))

	_, status, err := s.Transcribe(accessTokenFor(t, "u"), b64)
	if err == nil {
		t.Fatal("expected error for student")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestSTTSvc_Transcribe_InvalidToken(t *testing.T) {
	s := newSTTSvc(model.RoleTeacher)

	_, status, err := s.Transcribe("bad.token", "anything")
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestSTTSvc_Transcribe_MissingAudio(t *testing.T) {
	s := newSTTSvc(model.RoleTeacher)

	_, status, err := s.Transcribe(accessTokenFor(t, "u"), "")
	if err == nil {
		t.Fatal("expected error for empty audio")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}
