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

// --- SetName ---

func TestGroupSvc_SetName_MemberSucceeds(t *testing.T) {
	s, r := newGroupSvc()

	status, err := s.SetName(tokenFor(t, "alice"), 1, "Red Team")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if r.Names[1] != "Red Team" {
		t.Errorf("expected group 1 named %q, got %q", "Red Team", r.Names[1])
	}
}

func TestGroupSvc_SetName_TeacherBypassesMembership(t *testing.T) {
	s, r := newGroupSvc()

	// teacher is in no group but may rename any group.
	status, err := s.SetName(tokenFor(t, "teacher"), 2, "Blue Team")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if r.Names[2] != "Blue Team" {
		t.Errorf("expected group 2 named %q, got %q", "Blue Team", r.Names[2])
	}
}

func TestGroupSvc_SetName_NonMemberForbidden(t *testing.T) {
	s, _ := newGroupSvc()

	// carol (student) belongs to group 2, not group 1.
	status, err := s.SetName(tokenFor(t, "carol"), 1, "Nope")
	if err == nil {
		t.Fatal("expected error for non-member, non-teacher caller")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestGroupSvc_SetName_InvalidToken(t *testing.T) {
	s, _ := newGroupSvc()
	status, err := s.SetName("bad.token", 1, "X")
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

// --- SetBuilding ---

func TestGroupSvc_SetBuilding_MemberSucceeds(t *testing.T) {
	s, r := newGroupSvc()

	status, err := s.SetBuilding(tokenFor(t, "alice"), 1, 3)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if r.BuildingIDs[1] != 3 {
		t.Errorf("expected group 1 building 3, got %d", r.BuildingIDs[1])
	}
}

func TestGroupSvc_SetBuilding_TeacherBypassesMembership(t *testing.T) {
	s, r := newGroupSvc()

	status, err := s.SetBuilding(tokenFor(t, "teacher"), 2, 9)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if r.BuildingIDs[2] != 9 {
		t.Errorf("expected group 2 building 9, got %d", r.BuildingIDs[2])
	}
}

func TestGroupSvc_SetBuilding_NonMemberForbidden(t *testing.T) {
	s, _ := newGroupSvc()

	// carol (student) belongs to group 2, not group 1.
	status, err := s.SetBuilding(tokenFor(t, "carol"), 1, 3)
	if err == nil {
		t.Fatal("expected error for non-member, non-teacher caller")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestGroupSvc_SetBuilding_InvalidToken(t *testing.T) {
	s, _ := newGroupSvc()
	status, err := s.SetBuilding("bad.token", 1, 3)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

// --- SetProfilePic ---

func TestGroupSvc_SetProfilePic_MemberSucceeds(t *testing.T) {
	s, r := newGroupSvc()

	status, err := s.SetProfilePic(tokenFor(t, "alice"), 1, "/images/g1.png")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if r.Pics[1] != "/images/g1.png" {
		t.Errorf("expected group 1 pic %q, got %q", "/images/g1.png", r.Pics[1])
	}
}

func TestGroupSvc_SetProfilePic_TeacherBypassesMembership(t *testing.T) {
	s, r := newGroupSvc()

	status, err := s.SetProfilePic(tokenFor(t, "teacher"), 2, "/images/g2.png")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if r.Pics[2] != "/images/g2.png" {
		t.Errorf("expected group 2 pic %q, got %q", "/images/g2.png", r.Pics[2])
	}
}

func TestGroupSvc_SetProfilePic_NonMemberForbidden(t *testing.T) {
	s, _ := newGroupSvc()

	// carol (student) belongs to group 2, not group 1.
	status, err := s.SetProfilePic(tokenFor(t, "carol"), 1, "/images/x.png")
	if err == nil {
		t.Fatal("expected error for non-member, non-teacher caller")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestGroupSvc_SetProfilePic_InvalidToken(t *testing.T) {
	s, _ := newGroupSvc()
	status, err := s.SetProfilePic("bad.token", 1, "/images/x.png")
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

// --- DeleteGroup ---

func TestGroupSvc_DeleteGroup_TeacherSucceeds(t *testing.T) {
	s, r := newGroupSvc()

	status, err := s.DeleteGroup(tokenFor(t, "teacher"), 1)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	// Former members (alice, bob) are reset to no group.
	if r.UserGroups["alice"] != 0 || r.UserGroups["bob"] != 0 {
		t.Errorf("expected alice/bob reset to group 0, got %d/%d", r.UserGroups["alice"], r.UserGroups["bob"])
	}
	// carol (group 2) is untouched.
	if r.UserGroups["carol"] != 2 {
		t.Errorf("expected carol to remain in group 2, got %d", r.UserGroups["carol"])
	}
}

func TestGroupSvc_DeleteGroup_NotFound(t *testing.T) {
	s, _ := newGroupSvc()

	status, err := s.DeleteGroup(tokenFor(t, "teacher"), 99)
	if err == nil {
		t.Fatal("expected error for group nobody references")
	}
	if status != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", status)
	}
}

func TestGroupSvc_DeleteGroup_StudentForbidden(t *testing.T) {
	s, _ := newGroupSvc()

	// alice is a member of group 1 but only a student.
	status, err := s.DeleteGroup(tokenFor(t, "alice"), 1)
	if err == nil {
		t.Fatal("expected error for student caller")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestGroupSvc_DeleteGroup_InvalidToken(t *testing.T) {
	s, _ := newGroupSvc()
	status, err := s.DeleteGroup("bad.token", 1)
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
	var resp model.Group
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if resp.ID != 2 {
		t.Errorf("expected group_id 2, got %d", resp.ID)
	}
	if resp.Name != "Group 2" {
		t.Errorf("expected default name %q, got %q", "Group 2", resp.Name)
	}
	if len(resp.Members) != 1 || resp.Members[0] != "carol" {
		t.Errorf("expected members [carol], got %v", resp.Members)
	}
}

func TestGroupSvc_QueryGroup_CustomName(t *testing.T) {
	s, _ := newGroupSvc()

	if _, err := s.SetName(tokenFor(t, "carol"), 2, "Wolves"); err != nil {
		t.Fatalf("SetName: %v", err)
	}
	data, _, err := s.QueryGroup(tokenFor(t, "carol"))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	var resp model.Group
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if resp.Name != "Wolves" {
		t.Errorf("expected name %q, got %q", "Wolves", resp.Name)
	}
}

func TestGroupSvc_QueryGroup_BuildingID(t *testing.T) {
	s, _ := newGroupSvc()

	// default: no building assigned.
	data, _, err := s.QueryGroup(tokenFor(t, "carol"))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	var resp model.Group
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if resp.BuildingID != 0 {
		t.Errorf("expected default building_id 0, got %d", resp.BuildingID)
	}

	// after assignment it is reflected.
	if _, err := s.SetBuilding(tokenFor(t, "carol"), 2, 7); err != nil {
		t.Fatalf("SetBuilding: %v", err)
	}
	data, _, err = s.QueryGroup(tokenFor(t, "carol"))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if resp.BuildingID != 7 {
		t.Errorf("expected building_id 7, got %d", resp.BuildingID)
	}
}

func TestGroupSvc_QueryGroup_ProfilePic(t *testing.T) {
	s, _ := newGroupSvc()

	if _, err := s.SetProfilePic(tokenFor(t, "carol"), 2, "/images/wolves.png"); err != nil {
		t.Fatalf("SetProfilePic: %v", err)
	}
	data, _, err := s.QueryGroup(tokenFor(t, "carol"))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	var resp model.Group
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if resp.ProfilePicURL != "/images/wolves.png" {
		t.Errorf("expected pic %q, got %q", "/images/wolves.png", resp.ProfilePicURL)
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

// A caller whose group_id points to a group that has no stored data and no
// members gets a 404 rather than a fabricated empty group.
func TestGroupSvc_QueryGroup_GroupNotFound(t *testing.T) {
	r := &mock.GroupRepo{UserGroups: map[string]uint{}}
	users := &mock.AuthRepo{
		Roles:  map[string]uint{"ghost": model.RoleStudent},
		Groups: map[string]uint{"ghost": 7},
	}
	s := NewGroupSvc(r, users)

	_, status, err := s.QueryGroup(tokenFor(t, "ghost"))
	if err == nil {
		t.Fatal("expected error for nonexistent group")
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
