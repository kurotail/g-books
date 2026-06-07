package service

import (
	"encoding/json"
	"net/http"
	"testing"

	"gb-api/internal/model"
	"gb-api/internal/repo/mock"
)

func newMockGroupRepo() *mock.GroupRepo {
	return &mock.GroupRepo{
		UserGroups: map[string]uint{"alice": 1, "bob": 1, "carol": 2},
	}
}

// tokenFor mints a valid access token for the given username.
func tokenFor(t *testing.T, username string) string {
	t.Helper()
	tok, err := newTestAuthSvc().newAccessToken(username)
	if err != nil {
		t.Fatalf("failed to mint access token: %v", err)
	}
	return tok
}

func newGroupSvc() (*GroupSvc, *mock.GroupRepo) {
	r := newMockGroupRepo()
	users := &mock.AuthRepo{
		Roles: map[string]uint{
			"teacher": model.RoleTeacher,
			"student": model.RoleStudent,
			"alice":   model.RoleStudent,
			"bob":     model.RoleStudent,
			"carol":   model.RoleStudent,
		},
		Groups: map[string]uint{"alice": 1, "bob": 1, "carol": 2},
	}
	return NewGroupSvc(r, users), r
}

// --- SetGroup ---

func TestGroupSvc_SetGroup_TeacherSucceeds(t *testing.T) {
	s, r := newGroupSvc()

	status, err := s.SetGroup(tokenFor(t, "teacher"), "alice", 5)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if r.UserGroups["alice"] != 5 {
		t.Errorf("expected alice in group 5, got %d", r.UserGroups["alice"])
	}
}

func TestGroupSvc_SetGroup_StudentForbidden(t *testing.T) {
	s, _ := newGroupSvc()

	status, err := s.SetGroup(tokenFor(t, "student"), "alice", 5)
	if err == nil {
		t.Fatal("expected error for student caller")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestGroupSvc_SetGroup_UnknownUser(t *testing.T) {
	s, _ := newGroupSvc()

	status, err := s.SetGroup(tokenFor(t, "teacher"), "nobody", 5)
	if err == nil {
		t.Fatal("expected error for unknown target user")
	}
	if status != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", status)
	}
}

func TestGroupSvc_SetGroup_InvalidToken(t *testing.T) {
	s, _ := newGroupSvc()
	status, err := s.SetGroup("bad.token", "alice", 5)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

// --- QueryGroup ---

func TestGroupSvc_QueryGroup_Member(t *testing.T) {
	s, _ := newGroupSvc()

	data, status, err := s.QueryGroup(tokenFor(t, "carol"))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var resp model.GroupResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if resp.GroupID != 2 {
		t.Errorf("expected group_id 2, got %d", resp.GroupID)
	}
}

func TestGroupSvc_QueryGroup_NonMember(t *testing.T) {
	s, _ := newGroupSvc()

	_, status, err := s.QueryGroup(tokenFor(t, "teacher"))
	if err == nil {
		t.Fatal("expected error for user without a group")
	}
	if status != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", status)
	}
}

func TestGroupSvc_QueryGroup_InvalidToken(t *testing.T) {
	s, _ := newGroupSvc()
	_, status, err := s.QueryGroup("bad.token")
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

// --- QueryMember ---

func TestGroupSvc_QueryMember_ReturnsMembers(t *testing.T) {
	s, _ := newGroupSvc()

	data, status, err := s.QueryMember(tokenFor(t, "alice"), 1)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var resp model.MembersResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if resp.GroupID != 1 {
		t.Errorf("expected group_id 1, got %d", resp.GroupID)
	}
	got := map[string]bool{}
	for _, m := range resp.Members {
		got[m] = true
	}
	if len(resp.Members) != 2 || !got["alice"] || !got["bob"] {
		t.Errorf("expected members [alice bob], got %v", resp.Members)
	}
}

func TestGroupSvc_QueryMember_EmptyGroup(t *testing.T) {
	s, _ := newGroupSvc()

	data, status, err := s.QueryMember(tokenFor(t, "alice"), 99)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var resp model.MembersResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if len(resp.Members) != 0 {
		t.Errorf("expected no members, got %v", resp.Members)
	}
}

func TestGroupSvc_QueryMember_InvalidToken(t *testing.T) {
	s, _ := newGroupSvc()
	_, status, err := s.QueryMember("bad.token", 1)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}
