package service

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"gb-api/internal/model"
	"gb-api/internal/repo/mock"
)

// newRoleRepo returns a UserRepo mock that reports role for username. StateSvc
// only consults GetRole, so the other user fields are left empty.
func newRoleRepo(username string, role uint) *mock.AuthRepo {
	return &mock.AuthRepo{Roles: map[string]uint{username: role}}
}

func TestStateSvc_SetState_TeacherTransitions(t *testing.T) {
	t.Cleanup(func() { setStateUntil(model.StateNormal, time.Time{}) })
	s := NewStateSvc(newRoleRepo("teacher", model.RoleTeacher))

	data, status, err := s.SetState(accessTokenFor(t, "teacher"), model.StateQuiz2, nil)
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
	if resp.State != model.StateQuiz2 {
		t.Errorf("expected response state QUIZ, got %q", resp.State)
	}
	if getState() != model.StateQuiz2 {
		t.Errorf("expected package state QUIZ, got %q", getState())
	}
}

func TestStateSvc_SetState_EndTimeScheduledAndOverwritten(t *testing.T) {
	t.Cleanup(func() { setStateUntil(model.StateNormal, time.Time{}) })
	s := NewStateSvc(newRoleRepo("teacher", model.RoleTeacher))

	end1 := time.Now().Add(time.Hour).UTC().Round(time.Second)
	data, status, err := s.SetState(accessTokenFor(t, "teacher"), model.StateQuiz2, &end1)
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
	if resp.EndTime == nil || !resp.EndTime.Equal(end1) {
		t.Fatalf("expected end_time %v, got %v", end1, resp.EndTime)
	}

	// A second request overwrites the previous schedule.
	end2 := time.Now().Add(2 * time.Hour).UTC().Round(time.Second)
	data, _, err = s.SetState(accessTokenFor(t, "teacher"), model.StateQuiz1, &end2)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if resp.State != model.StateQuiz1 {
		t.Errorf("expected QUIZ1, got %q", resp.State)
	}
	if resp.EndTime == nil || !resp.EndTime.Equal(end2) {
		t.Errorf("expected overwritten end_time %v, got %v", end2, resp.EndTime)
	}
}

func TestStateSvc_SetState_PastEndTimeRejected(t *testing.T) {
	t.Cleanup(func() { setStateUntil(model.StateNormal, time.Time{}) })
	s := NewStateSvc(newRoleRepo("teacher", model.RoleTeacher))

	past := time.Now().Add(-time.Minute)
	_, status, err := s.SetState(accessTokenFor(t, "teacher"), model.StateQuiz2, &past)
	if err == nil {
		t.Fatal("expected error for past end_time")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestRevertIfDue(t *testing.T) {
	t.Cleanup(func() { setStateUntil(model.StateNormal, time.Time{}) })

	// Not due: end time in the future is left untouched.
	future := time.Now().Add(time.Hour)
	setStateUntil(model.StateQuiz2, future)
	revertIfDue(time.Now())
	if getState() != model.StateQuiz2 {
		t.Fatalf("expected QUIZ2 to remain, got %q", getState())
	}

	// Due: end time in the past reverts to NORMAL and clears the schedule.
	past := time.Now().Add(-time.Second)
	setStateUntil(model.StateQuiz2, past)
	revertIfDue(time.Now())
	if getState() != model.StateNormal {
		t.Fatalf("expected NORMAL after revert, got %q", getState())
	}
	snap := stateSnapshot()
	if snap.EndTime != nil {
		t.Errorf("expected end_time cleared after revert, got %v", snap.EndTime)
	}

	// No schedule: revert is a no-op.
	setStateUntil(model.StateQuiz1, time.Time{})
	revertIfDue(time.Now())
	if getState() != model.StateQuiz1 {
		t.Errorf("expected QUIZ1 to remain with no schedule, got %q", getState())
	}
}

func TestStateSvc_SetState_StudentForbidden(t *testing.T) {
	s := NewStateSvc(newRoleRepo("student", model.RoleStudent))

	_, status, err := s.SetState(accessTokenFor(t, "student"), model.StateQuiz2, nil)
	if err == nil {
		t.Fatal("expected error for student role")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestStateSvc_SetState_InvalidValue(t *testing.T) {
	s := NewStateSvc(newRoleRepo("teacher", model.RoleTeacher))

	_, status, err := s.SetState(accessTokenFor(t, "teacher"), model.ServerState("BOGUS"), nil)
	if err == nil {
		t.Fatal("expected error for invalid state")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestStateSvc_GetState(t *testing.T) {
	useState(t, model.StateQuiz2)
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
	if resp.State != model.StateQuiz2 {
		t.Errorf("expected QUIZ, got %q", resp.State)
	}
	if resp.UpdatedAt.IsZero() {
		t.Error("expected GetState to return a non-zero updated_at")
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
	if cur.State != model.StateNormal {
		t.Errorf("expected snapshot NORMAL, got %q", cur.State)
	}
	if cur.UpdatedAt.IsZero() {
		t.Error("expected snapshot to carry a non-zero updated_at")
	}

	setStateUntil(model.StateQuiz2, time.Time{})
	select {
	case got := <-events:
		if got.State != model.StateQuiz2 {
			t.Errorf("expected QUIZ event, got %q", got.State)
		}
		if got.UpdatedAt.IsZero() {
			t.Error("expected event to carry a non-zero updated_at")
		}
	default:
		t.Fatal("expected a QUIZ transition event")
	}
}
