package service

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"gb-api/internal/model"
	"gb-api/internal/repo"
)

type QuestionSvc struct {
	repo repo.QuestionRepo
}

func NewQuestionSvc(r repo.QuestionRepo) *QuestionSvc {
	return &QuestionSvc{repo: r}
}

// Generate issues a new question session. Only users with permission higher
// than Student may call it.
func (s *QuestionSvc) Generate(accessToken string, groupID uint) ([]byte, int, error) {
	claims, err := validateAccessToken(accessToken)
	if err != nil {
		return nil, http.StatusUnauthorized, err
	}
	perm, err := s.repo.GetPermission(claims.Username)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	// Teachers and admins may always generate; students only while the server
	// is in QUIZ state.
	if studentBlockedByState(perm) {
		return nil, http.StatusForbidden, fmt.Errorf("NORMAL 狀態下學生無法產生題目")
	}
	id, q, err := s.repo.CreateSession(groupID)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(model.QuestionResponse{Session: id, Description: q.Description})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

// Answer checks the submitted answer against a session, deletes the session
// (single-use), and reports whether the answer was correct. Teachers and admins
// may always answer; students only while the server is in QUIZ state.
func (s *QuestionSvc) Answer(accessToken, session string, ans uint) ([]byte, int, error) {
	claims, err := validateAccessToken(accessToken)
	if err != nil {
		return nil, http.StatusUnauthorized, err
	}
	perm, err := s.repo.GetPermission(claims.Username)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if studentBlockedByState(perm) {
		return nil, http.StatusForbidden, fmt.Errorf("NORMAL 狀態下學生無法作答")
	}
	qs, ok, err := s.repo.ConsumeSession(session)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if !ok {
		return nil, http.StatusBadRequest, fmt.Errorf("session 不存在或已使用")
	}
	if time.Now().After(qs.ExpiresAt) {
		return nil, http.StatusBadRequest, fmt.Errorf("session 已過期")
	}
	data, err := json.Marshal(model.AnswerResponse{Correct: ans == qs.Answer})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

// GetState returns the current global quiz state. Any authenticated user may read it.
func (s *QuestionSvc) GetState(accessToken string) ([]byte, int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return nil, http.StatusUnauthorized, err
	}
	data, err := json.Marshal(model.StateResponse{State: getState()})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

// SetState transitions the global quiz state. Only teachers and admins may call it.
func (s *QuestionSvc) SetState(accessToken string, state model.ServerState) ([]byte, int, error) {
	claims, err := validateAccessToken(accessToken)
	if err != nil {
		return nil, http.StatusUnauthorized, err
	}
	perm, err := s.repo.GetPermission(claims.Username)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if perm <= model.PermStudent {
		return nil, http.StatusForbidden, fmt.Errorf("權限不足")
	}
	if state != model.StateNormal && state != model.StateQuiz {
		return nil, http.StatusBadRequest, fmt.Errorf("不合法的狀態: %q", state)
	}
	setState(state)
	data, err := json.Marshal(model.StateResponse{State: state})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}
