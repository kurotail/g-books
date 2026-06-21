package handler

import (
	"encoding/json"
	"net/http"
	"strconv"

	"gb-api/internal/model"
	"gb-api/internal/service"
)

type StudentHandler struct {
	svc *service.StudentSvc
}

func NewStudentHandler(s *service.StudentSvc) *StudentHandler {
	return &StudentHandler{svc: s}
}

// Create adds a new student (teacher/admin only).
func (h *StudentHandler) Create(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.CreateStudentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	if req.StudentID == 0 {
		http.Error(w, "缺少 student_id", http.StatusBadRequest)
		return
	}
	if req.Name == "" {
		http.Error(w, "缺少 name", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.Create(token, req.StudentID, req.Name, req.ProfilePicURL)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

// Update replaces the student identified by the {id} path segment (teacher/admin only).
func (h *StudentHandler) Update(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	id, err := strconv.ParseUint(r.PathValue("id"), 10, 64)
	if err != nil {
		http.Error(w, "不合法的 student id", http.StatusBadRequest)
		return
	}
	var req model.CreateStudentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	if req.Name == "" {
		http.Error(w, "缺少 name", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.Update(token, uint(id), req.Name, req.ProfilePicURL)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

// Get returns the student identified by the {id} path segment.
func (h *StudentHandler) Get(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	id, err := strconv.ParseUint(r.PathValue("id"), 10, 64)
	if err != nil {
		http.Error(w, "不合法的 student id", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.Get(token, uint(id))
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

// List returns every student.
func (h *StudentHandler) List(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	data, status, err := h.svc.List(token)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

// SetStudents replaces a user's student roster with the given list (teacher/admin only).
// Returns 207 Multi-Status with a per-id result.
func (h *StudentHandler) SetStudents(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.SetStudentsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	if req.UserID == nil || *req.UserID == 0 {
		http.Error(w, "缺少 user_id", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.SetStudents(token, *req.UserID, req.StudentIDs)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSONStatus(w, status, data)
}

// Delete removes the student identified by the {id} path segment (teacher/admin only).
func (h *StudentHandler) Delete(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	id, err := strconv.ParseUint(r.PathValue("id"), 10, 64)
	if err != nil {
		http.Error(w, "不合法的 student id", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.Delete(token, uint(id))
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}
