package service

import (
	"encoding/json"
	"net/http"
	"testing"

	"gb-api/internal/model"
	"gb-api/internal/repo/mock"
)

// newRoleRepo returns a UserRepo mock that reports role for username. StateSvc
// only consults GetRole, so the other user fields are left empty.
func newRoleRepo(username string, role uint) *mock.AuthRepo {
	return &mock.AuthRepo{Roles: map[string]uint{username: role}}
}

func TestStateSvc_SetState_TeacherTransitions(t *testing.T) {
	t.Cleanup(func() { setState(model.StateNormal) })
	s := NewStateSvc(newRoleRepo("teacher", model.RoleTeacher))

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

func TestStateSvc_SetState_StudentForbidden(t *testing.T) {
	s := NewStateSvc(newRoleRepo("student", model.RoleStudent))

	_, status, err := s.SetState(accessTokenFor(t, "student"), model.StateQuiz)
	if err == nil {
		t.Fatal("expected error for student role")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestStateSvc_SetState_InvalidValue(t *testing.T) {
	s := NewStateSvc(newRoleRepo("teacher", model.RoleTeacher))

	_, status, err := s.SetState(accessTokenFor(t, "teacher"), model.ServerState("BOGUS"))
	if err == nil {
		t.Fatal("expected error for invalid state")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestStateSvc_GetState(t *testing.T) {
	useState(t, model.StateQuiz)
	s := NewStateSvc(newRoleRepo("anyone", model.RoleStudent))

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

// SubscribeState delivers the current state as the snapshot and then every
// subsequent transition.
func TestStateSvc_SubscribeState(t *testing.T) {
	useState(t, model.StateNormal)
	s := NewStateSvc(newRoleRepo("anyone", model.RoleStudent))

	cur, events, unsub, status, err := s.SubscribeState(accessTokenFor(t, "anyone"))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	defer unsub()
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if cur != model.StateNormal {
		t.Errorf("expected snapshot NORMAL, got %q", cur)
	}

	setState(model.StateQuiz)
	select {
	case got := <-events:
		if got != model.StateQuiz {
			t.Errorf("expected QUIZ event, got %q", got)
		}
	default:
		t.Fatal("expected a QUIZ transition event")
	}
}
