package handler

import (
	"encoding/json"
	"net/http"
	"strconv"

	"gb-api/internal/model"
	"gb-api/internal/service"
)

type QuestionHandler struct {
	svc *service.QuestionSvc
}

func NewQuestionHandler(s *service.QuestionSvc) *QuestionHandler {
	return &QuestionHandler{svc: s}
}

func (h *QuestionHandler) Generate(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.GenerateQuestionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.Generate(token, req.GroupID)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

// Upload appends a batch of teacher-supplied questions to the pool.
func (h *QuestionHandler) Upload(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.UploadQuestionsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.Upload(token, req.Questions)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSONStatus(w, status, data)
}

// Search returns pool questions matching the ?q= query parameter.
func (h *QuestionHandler) Search(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	data, status, err := h.svc.Search(token, r.URL.Query().Get("q"))
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

// Update overwrites the question identified by the {id} path segment.
func (h *QuestionHandler) Update(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	id, err := strconv.ParseUint(r.PathValue("id"), 10, 64)
	if err != nil {
		http.Error(w, "不合法的 question id", http.StatusBadRequest)
		return
	}
	var req model.QuestionInput
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	status, err := h.svc.Update(token, uint(id), req)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	w.WriteHeader(status)
}

// Delete removes the question identified by the {id} path segment.
func (h *QuestionHandler) Delete(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	id, err := strconv.ParseUint(r.PathValue("id"), 10, 64)
	if err != nil {
		http.Error(w, "不合法的 question id", http.StatusBadRequest)
		return
	}
	status, err := h.svc.Delete(token, uint(id))
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	w.WriteHeader(status)
}

func (h *QuestionHandler) Answer(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.AnswerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	if req.Session == "" {
		http.Error(w, "缺少 session", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.Answer(token, req.Session, req.Answer)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}
