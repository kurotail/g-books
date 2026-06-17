package service

import (
	"encoding/json"
	"net/http"
	"testing"

	"gb-api/internal/model"
	"gb-api/internal/repo/mock"
)

func newStudentSvc() (*StudentSvc, *mock.StudentRepo) {
	r := &mock.StudentRepo{
		Students: map[uint]model.Student{
			1: {StudentID: 1, Name: "Alice", ProfilePicURL: "/images/a.jpg"},
		},
		NextID: 2,
	}
	users := &mock.AuthRepo{
		Roles: map[string]uint{
			"teacher": model.RoleTeacher,
			"student": model.RoleStudent,
		},
	}
	return NewStudentSvc(r, users), r
}

func TestStudentSvc_Create_TeacherSucceeds(t *testing.T) {
	s, r := newStudentSvc()

	data, status, err := s.Create(tokenFor(t, "teacher"), "Bob", "/images/b.jpg")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}

	var resp model.Student
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if resp.Name != "Bob" || resp.ProfilePicURL != "/images/b.jpg" || resp.StudentID == 0 {
		t.Errorf("unexpected response: %+v", resp)
	}
	if stored := r.Students[resp.StudentID]; stored.Name != "Bob" {
		t.Errorf("store not updated: %+v", stored)
	}
}

func TestStudentSvc_Create_StudentForbidden(t *testing.T) {
	s, _ := newStudentSvc()

	_, status, err := s.Create(tokenFor(t, "student"), "Bob", "")
	if err == nil {
		t.Fatal("expected error for student caller")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestStudentSvc_Update_TeacherSucceeds(t *testing.T) {
	s, r := newStudentSvc()

	data, status, err := s.Update(tokenFor(t, "teacher"), 1, "Alice2", "/images/a2.jpg")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}

	var resp model.Student
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if resp.Name != "Alice2" || resp.ProfilePicURL != "/images/a2.jpg" {
		t.Errorf("unexpected response: %+v", resp)
	}
	if stored := r.Students[1]; stored.Name != "Alice2" {
		t.Errorf("store not updated: %+v", stored)
	}
}

func TestStudentSvc_Update_StudentForbidden(t *testing.T) {
	s, _ := newStudentSvc()

	_, status, err := s.Update(tokenFor(t, "student"), 1, "New", "")
	if err == nil {
		t.Fatal("expected error for student caller")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestStudentSvc_Update_NotFound(t *testing.T) {
	s, _ := newStudentSvc()

	_, status, err := s.Update(tokenFor(t, "teacher"), 999, "New", "")
	if err == nil {
		t.Fatal("expected error for unknown student")
	}
	if status != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", status)
	}
}

func TestStudentSvc_Delete_TeacherSucceeds(t *testing.T) {
	s, r := newStudentSvc()

	_, status, err := s.Delete(tokenFor(t, "teacher"), 1)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if _, ok := r.Students[1]; ok {
		t.Error("expected student to be deleted from store")
	}
}

func TestStudentSvc_Delete_StudentForbidden(t *testing.T) {
	s, _ := newStudentSvc()

	_, status, err := s.Delete(tokenFor(t, "student"), 1)
	if err == nil {
		t.Fatal("expected error for student caller")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestStudentSvc_Delete_NotFound(t *testing.T) {
	s, _ := newStudentSvc()

	_, status, err := s.Delete(tokenFor(t, "teacher"), 999)
	if err == nil {
		t.Fatal("expected error for unknown student")
	}
	if status != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", status)
	}
}

func TestStudentSvc_Get_StudentAllowed(t *testing.T) {
	s, _ := newStudentSvc()

	data, status, err := s.Get(tokenFor(t, "student"), 1)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var resp model.Student
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if resp.StudentID != 1 || resp.Name != "Alice" {
		t.Errorf("unexpected response: %+v", resp)
	}
}

func TestStudentSvc_Get_NotFound(t *testing.T) {
	s, _ := newStudentSvc()

	_, status, err := s.Get(tokenFor(t, "student"), 999)
	if err == nil {
		t.Fatal("expected error for unknown student")
	}
	if status != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", status)
	}
}

func TestStudentSvc_List_StudentAllowed(t *testing.T) {
	s, _ := newStudentSvc()

	data, status, err := s.List(tokenFor(t, "student"))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var resp []model.Student
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if len(resp) != 1 {
		t.Errorf("expected 1 student, got %d", len(resp))
	}
}

func TestStudentSvc_Create_InvalidToken(t *testing.T) {
	s, _ := newStudentSvc()

	_, status, err := s.Create("bad.token", "Bob", "")
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}
