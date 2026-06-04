package service

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"gb-api/internal/model"
	"gb-api/internal/repo/mock"
)

func newMockQuestionRepo(role uint) *mock.QuestionRepo {
	return &mock.QuestionRepo{
		Role:     role,
		Sessions: map[string]model.QuestionSession{},
	}
}

func accessTokenFor(t *testing.T, username string) string {
	t.Helper()
	tok, err := newTestAuthSvc().newAccessToken(username)
	if err != nil {
		t.Fatalf("failed to mint access token: %v", err)
	}
	return tok
}

// useState sets the package-level quiz state for the duration of a test and
// restores StateNormal afterwards.
func useState(t *testing.T, s model.ServerState) {
	t.Helper()
	setState(s)
	t.Cleanup(func() { setState(model.StateNormal) })
}

// --- Generate ---

func TestQuestionSvc_Generate_TeacherSucceeds(t *testing.T) {
	useAdvancingClock(t)
	r := newMockQuestionRepo(model.RoleTeacher)
	s := NewQuestionSvc(r)

	data, status, err := s.Generate(accessTokenFor(t, "teacher"), 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	// Response must carry a session + description but never leak the answer.
	var raw map[string]any
	if err := json.Unmarshal(data, &raw); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if raw["session"] == "" || raw["session"] == nil {
		t.Error("expected a session in response")
	}
	if raw["description"] == nil {
		t.Error("expected a description in response")
	}
	if _, leaked := raw["Answer"]; leaked {
		t.Error("response must not contain the answer")
	}
	if _, leaked := raw["answer"]; leaked {
		t.Error("response must not contain the answer")
	}
}

func TestQuestionSvc_Generate_StudentForbiddenInNormal(t *testing.T) {
	useAdvancingClock(t)
	s := NewQuestionSvc(newMockQuestionRepo(model.RoleStudent))

	_, status, err := s.Generate(accessTokenFor(t, "student"), 0)
	if err == nil {
		t.Fatal("expected error for student in NORMAL state")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestQuestionSvc_Generate_InvalidToken(t *testing.T) {
	s := NewQuestionSvc(newMockQuestionRepo(model.RoleAdmin))

	_, status, err := s.Generate("bad.token", 0)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestQuestionSvc_Generate_StudentAllowedInQuizState(t *testing.T) {
	useAdvancingClock(t)
	useState(t, model.StateQuiz)
	s := NewQuestionSvc(newMockQuestionRepo(model.RoleStudent))

	_, status, err := s.Generate(accessTokenFor(t, "student"), 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
}

// --- State ---

func TestQuestionSvc_SetState_TeacherTransitions(t *testing.T) {
	useAdvancingClock(t)
	t.Cleanup(func() { setState(model.StateNormal) })
	s := NewQuestionSvc(newMockQuestionRepo(model.RoleTeacher))

	data, status, err := s.SetState(accessTokenFor(t, "teacher"), model.StateQuiz)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var resp model.StateResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if resp.State != model.StateQuiz {
		t.Errorf("expected response state QUIZ, got %q", resp.State)
	}
	if getState() != model.StateQuiz {
		t.Errorf("expected package state QUIZ, got %q", getState())
	}
}

func TestQuestionSvc_SetState_StudentForbidden(t *testing.T) {
	useAdvancingClock(t)
	s := NewQuestionSvc(newMockQuestionRepo(model.RoleStudent))

	_, status, err := s.SetState(accessTokenFor(t, "student"), model.StateQuiz)
	if err == nil {
		t.Fatal("expected error for student role")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestQuestionSvc_SetState_InvalidValue(t *testing.T) {
	useAdvancingClock(t)
	s := NewQuestionSvc(newMockQuestionRepo(model.RoleTeacher))

	_, status, err := s.SetState(accessTokenFor(t, "teacher"), model.ServerState("BOGUS"))
	if err == nil {
		t.Fatal("expected error for invalid state")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestQuestionSvc_GetState(t *testing.T) {
	useAdvancingClock(t)
	useState(t, model.StateQuiz)
	s := NewQuestionSvc(newMockQuestionRepo(model.RoleStudent))

	data, status, err := s.GetState(accessTokenFor(t, "anyone"))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var resp model.StateResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if resp.State != model.StateQuiz {
		t.Errorf("expected QUIZ, got %q", resp.State)
	}
}

// --- Answer ---

func TestQuestionSvc_Answer_Correct(t *testing.T) {
	useAdvancingClock(t)
	useState(t, model.StateQuiz) // let the student through the gate
	r := newMockQuestionRepo(model.RoleStudent)
	s := NewQuestionSvc(r)
	r.CreateSession(0) // seeds answer = 1
	id := r.Created

	data, status, err := s.Answer(accessTokenFor(t, "student"), id, 1)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var resp model.AnswerResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if !resp.Correct {
		t.Error("expected correct=true")
	}
	// Session must be deleted (single-use).
	if _, ok := r.Sessions[id]; ok {
		t.Error("expected session to be deleted after answering")
	}
}

func TestQuestionSvc_Answer_Wrong(t *testing.T) {
	useAdvancingClock(t)
	useState(t, model.StateQuiz)
	r := newMockQuestionRepo(model.RoleStudent)
	s := NewQuestionSvc(r)
	r.CreateSession(0)
	id := r.Created

	data, status, err := s.Answer(accessTokenFor(t, "student"), id, 3)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var resp model.AnswerResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if resp.Correct {
		t.Error("expected correct=false")
	}
}

func TestQuestionSvc_Answer_StudentForbiddenInNormal(t *testing.T) {
	useAdvancingClock(t)
	r := newMockQuestionRepo(model.RoleStudent)
	s := NewQuestionSvc(r)
	r.CreateSession(0)
	id := r.Created

	_, status, err := s.Answer(accessTokenFor(t, "student"), id, 1)
	if err == nil {
		t.Fatal("expected error for student in NORMAL state")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
	// The gate must reject before the session is consumed.
	if _, ok := r.Sessions[id]; !ok {
		t.Error("session must not be consumed when answering is forbidden")
	}
}

func TestQuestionSvc_Answer_TeacherAllowedInNormal(t *testing.T) {
	useAdvancingClock(t)
	r := newMockQuestionRepo(model.RoleTeacher)
	s := NewQuestionSvc(r)
	r.CreateSession(0)
	id := r.Created

	_, status, err := s.Answer(accessTokenFor(t, "teacher"), id, 1)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
}

func TestQuestionSvc_Answer_UnknownSession(t *testing.T) {
	useAdvancingClock(t)
	useState(t, model.StateQuiz)
	s := NewQuestionSvc(newMockQuestionRepo(model.RoleStudent))

	_, status, err := s.Answer(accessTokenFor(t, "student"), "nope", 1)
	if err == nil {
		t.Fatal("expected error for unknown session")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestQuestionSvc_Answer_Expired(t *testing.T) {
	useAdvancingClock(t)
	useState(t, model.StateQuiz)
	r := newMockQuestionRepo(model.RoleStudent)
	s := NewQuestionSvc(r)
	r.Sessions["expired"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(-time.Minute),
		Question:  model.Question{Answer: 1},
	}

	_, status, err := s.Answer(accessTokenFor(t, "student"), "expired", 1)
	if err == nil {
		t.Fatal("expected error for expired session")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestQuestionSvc_Answer_InvalidToken(t *testing.T) {
	s := NewQuestionSvc(newMockQuestionRepo(model.RoleStudent))

	_, status, err := s.Answer("bad.token", "session-id", 1)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}
