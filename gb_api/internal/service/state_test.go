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

// stateCtl drives the global state machine in tests. The state vars are package-level,
// so any StateSvc instance mutates the same state; this one is used wherever a test
// just needs to set/revert state without caring about the block-clearing target.
var stateCtl = NewStateSvc(&mock.AuthRepo{}, &mock.ItemRepo{}, &mock.ScoreRepo{})

func TestStateSvc_SetState_TeacherTransitions(t *testing.T) {
	t.Cleanup(func() { stateCtl.setStateUntil(model.StateNormal, time.Time{}) })
	s := NewStateSvc(newRoleRepo("teacher", model.RoleTeacher), &mock.ItemRepo{}, &mock.ScoreRepo{})

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
	t.Cleanup(func() { stateCtl.setStateUntil(model.StateNormal, time.Time{}) })
	s := NewStateSvc(newRoleRepo("teacher", model.RoleTeacher), &mock.ItemRepo{}, &mock.ScoreRepo{})

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
	t.Cleanup(func() { stateCtl.setStateUntil(model.StateNormal, time.Time{}) })
	s := NewStateSvc(newRoleRepo("teacher", model.RoleTeacher), &mock.ItemRepo{}, &mock.ScoreRepo{})

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
	t.Cleanup(func() { stateCtl.setStateUntil(model.StateNormal, time.Time{}) })

	// Not due: end time in the future is left untouched.
	future := time.Now().Add(time.Hour)
	stateCtl.setStateUntil(model.StateQuiz2, future)
	stateCtl.revertIfDue(time.Now())
	if getState() != model.StateQuiz2 {
		t.Fatalf("expected QUIZ2 to remain, got %q", getState())
	}

	// Due: end time in the past reverts to NORMAL and clears the schedule.
	past := time.Now().Add(-time.Second)
	stateCtl.setStateUntil(model.StateQuiz2, past)
	stateCtl.revertIfDue(time.Now())
	if getState() != model.StateNormal {
		t.Fatalf("expected NORMAL after revert, got %q", getState())
	}
	snap := stateSnapshot()
	if snap.EndTime != nil {
		t.Errorf("expected end_time cleared after revert, got %v", snap.EndTime)
	}

	// No schedule: revert is a no-op.
	stateCtl.setStateUntil(model.StateQuiz1, time.Time{})
	stateCtl.revertIfDue(time.Now())
	if getState() != model.StateQuiz1 {
		t.Errorf("expected QUIZ1 to remain with no schedule, got %q", getState())
	}
}

// Returning to NORMAL — whether via an explicit SetState or the scheduled
// auto-revert — wipes every slot's attacker blocklist.
func TestStateSvc_NormalClearsAttackBlocks(t *testing.T) {
	t.Cleanup(func() { stateCtl.setStateUntil(model.StateNormal, time.Time{}) })
	blocks := &mock.ItemRepo{AttackBlocks: map[[3]uint]struct{}{{1, 0, 2}: {}}}
	s := NewStateSvc(newRoleRepo("teacher", model.RoleTeacher), blocks, &mock.ScoreRepo{})

	// Explicit transition to NORMAL clears the table.
	s.setStateUntil(model.StateQuiz2, time.Time{})
	if _, status, err := s.SetState(accessTokenFor(t, "teacher"), model.StateNormal, nil); err != nil || status != http.StatusOK {
		t.Fatalf("SetState NORMAL failed: status=%d err=%v", status, err)
	}
	if len(blocks.AttackBlocks) != 0 {
		t.Fatalf("expected attack blocks cleared on SetState NORMAL, got %v", blocks.AttackBlocks)
	}

	// Scheduled auto-revert to NORMAL also clears the table.
	blocks.AttackBlocks = map[[3]uint]struct{}{{1, 0, 2}: {}}
	s.setStateUntil(model.StateQuiz2, time.Now().Add(-time.Second))
	s.revertIfDue(time.Now())
	if getState() != model.StateNormal {
		t.Fatalf("expected NORMAL after revert, got %q", getState())
	}
	if len(blocks.AttackBlocks) != 0 {
		t.Errorf("expected attack blocks cleared on auto-revert, got %v", blocks.AttackBlocks)
	}
}

// Ending QUIZ2 recomputes and caches the leaderboard; GetState/GetScores then expose it.
func TestStateSvc_Quiz2EndComputesScores(t *testing.T) {
	t.Cleanup(func() { stateCtl.setStateUntil(model.StateNormal, time.Time{}) })
	want := []model.UserScore{{UserID: 1, Score: 5}, {UserID: 2, Score: 0}}
	scoreRepo := &mock.ScoreRepo{Sums: want}
	s := NewStateSvc(newRoleRepo("teacher", model.RoleTeacher), &mock.ItemRepo{}, scoreRepo)

	// Enter QUIZ2, then end it (QUIZ2 -> NORMAL) — this triggers the recompute.
	s.setStateUntil(model.StateQuiz2, time.Time{})
	if _, _, err := s.SetState(accessTokenFor(t, "teacher"), model.StateNormal, nil); err != nil {
		t.Fatalf("SetState NORMAL failed: %v", err)
	}

	data, _, err := s.GetScores(accessTokenFor(t, "teacher"))
	if err != nil {
		t.Fatalf("GetScores failed: %v", err)
	}
	var resp model.ScoresResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if len(resp.Scores) != 2 || resp.Scores[0] != want[0] || resp.Scores[1] != want[1] {
		t.Errorf("expected scores %v, got %v", want, resp.Scores)
	}

	// The state snapshot (and thus the WS broadcast) carries the same scores.
	data, _, _ = s.GetState(accessTokenFor(t, "teacher"))
	var st model.StateResponse
	json.Unmarshal(data, &st)
	if len(st.Scores) != 2 {
		t.Errorf("expected state snapshot to carry scores, got %v", st.Scores)
	}
}

// A transition that is not a QUIZ2 exit must not recompute scores.
func TestStateSvc_NonQuiz2EndLeavesScores(t *testing.T) {
	t.Cleanup(func() { stateCtl.setStateUntil(model.StateNormal, time.Time{}) })
	scoreRepo := &mock.ScoreRepo{Sums: []model.UserScore{{UserID: 9, Score: 9}}}
	s := NewStateSvc(newRoleRepo("teacher", model.RoleTeacher), &mock.ItemRepo{}, scoreRepo)

	// Seed a known cache via a QUIZ2 exit, then change what the repo would return.
	s.setStateUntil(model.StateQuiz2, time.Time{})
	s.setStateUntil(model.StateNormal, time.Time{})
	scoreRepo.Sums = []model.UserScore{{UserID: 1, Score: 100}} // would differ if recomputed

	// NORMAL -> QUIZ1 is not a QUIZ2 exit: the cache must stay as the QUIZ2-end snapshot.
	s.setStateUntil(model.StateQuiz1, time.Time{})

	data, _, _ := s.GetScores(accessTokenFor(t, "teacher"))
	var resp model.ScoresResponse
	json.Unmarshal(data, &resp)
	if len(resp.Scores) != 1 || resp.Scores[0].UserID != 9 {
		t.Errorf("expected the QUIZ2-end snapshot to persist, got %v", resp.Scores)
	}
}

func TestStateSvc_SetState_StudentForbidden(t *testing.T) {
	s := NewStateSvc(newRoleRepo("student", model.RoleStudent), &mock.ItemRepo{}, &mock.ScoreRepo{})

	_, status, err := s.SetState(accessTokenFor(t, "student"), model.StateQuiz2, nil)
	if err == nil {
		t.Fatal("expected error for student role")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestStateSvc_SetState_InvalidValue(t *testing.T) {
	s := NewStateSvc(newRoleRepo("teacher", model.RoleTeacher), &mock.ItemRepo{}, &mock.ScoreRepo{})

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
	s := NewStateSvc(newRoleRepo("anyone", model.RoleStudent), &mock.ItemRepo{}, &mock.ScoreRepo{})

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
	s := NewStateSvc(newRoleRepo("anyone", model.RoleStudent), &mock.ItemRepo{}, &mock.ScoreRepo{})

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

	stateCtl.setStateUntil(model.StateQuiz2, time.Time{})
	select {
	case msg := <-events:
		got, ok := msg.(model.StateResponse)
		if !ok {
			t.Fatalf("expected a StateResponse event, got %T", msg)
		}
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
