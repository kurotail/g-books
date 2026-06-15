package service

import (
	"encoding/json"
	"net/http"
	"testing"

	"gb-api/internal/model"
	"gb-api/internal/repo/mock"
)

func newBuildingSvc() (*BuildingSvc, *mock.BuildingRepo) {
	r := &mock.BuildingRepo{
		Buildings: map[uint]model.Building{
			1: {ID: 1, Name: "Old", Layout: "old-layout", TypeAllowedSlot: map[uint][]uint{10: {0}}, DifficultyType: map[uint][]uint{1: {10}}},
		},
		NextID: 2,
	}
	users := &mock.AuthRepo{
		Roles: map[string]uint{
			"teacher": model.RoleTeacher,
			"student": model.RoleStudent,
		},
	}
	return NewBuildingSvc(r, users), r
}

func TestBuildingSvc_Update_TeacherSucceeds(t *testing.T) {
	s, r := newBuildingSvc()

	data, status, err := s.Update(tokenFor(t, "teacher"), 1, "New", "new-layout",
		map[uint][]uint{20: {1, 2}}, map[uint][]uint{2: {20}})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}

	var resp model.Building
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if resp.ID != 1 || resp.Name != "New" || resp.Layout != "new-layout" {
		t.Errorf("unexpected response: %+v", resp)
	}
	// Stored record was fully replaced.
	stored := r.Buildings[1]
	if stored.Name != "New" || stored.Layout != "new-layout" {
		t.Errorf("store not updated: %+v", stored)
	}
	if got := stored.TypeAllowedSlot[20]; len(got) != 2 {
		t.Errorf("expected item_allowed_slot replaced, got %v", stored.TypeAllowedSlot)
	}
	if _, ok := stored.TypeAllowedSlot[10]; ok {
		t.Errorf("expected old item_allowed_slot key cleared, got %v", stored.TypeAllowedSlot)
	}
}

func TestBuildingSvc_Update_StudentForbidden(t *testing.T) {
	s, _ := newBuildingSvc()

	_, status, err := s.Update(tokenFor(t, "student"), 1, "New", "", nil, nil)
	if err == nil {
		t.Fatal("expected error for student caller")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestBuildingSvc_Update_NotFound(t *testing.T) {
	s, _ := newBuildingSvc()

	_, status, err := s.Update(tokenFor(t, "teacher"), 999, "New", "", nil, nil)
	if err == nil {
		t.Fatal("expected error for unknown building")
	}
	if status != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", status)
	}
}

func TestBuildingSvc_Update_InvalidToken(t *testing.T) {
	s, _ := newBuildingSvc()

	_, status, err := s.Update("bad.token", 1, "New", "", nil, nil)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}
