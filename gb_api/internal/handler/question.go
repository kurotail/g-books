package handler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
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
	if len(req.Questions) == 0 {
		http.Error(w, "缺少 questions", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.Upload(token, req.Questions)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSONStatus(w, status, data)
}

func optionalUint(q url.Values, key string) (*uint, error) {
	raw := q.Get(key)
	if raw == "" {
		return nil, nil
	}
	v, err := strconv.ParseUint(raw, 10, 64)
	if err != nil {
		return nil, fmt.Errorf("不合法的 %s", key)
	}
	u := uint(v)
	return &u, nil
}

// parseSearchFilters extracts the optional difficulty and area exact-match filters
// from the search query parameters.
func parseSearchFilters(q url.Values) (difficulty, area *uint, err error) {
	if difficulty, err = optionalUint(q, "difficulty"); err != nil {
		return nil, nil, err
	}
	if area, err = optionalUint(q, "area"); err != nil {
		return nil, nil, err
	}
	return difficulty, area, nil
}

// Search returns pool questions, optionally filtered by the exact-match ?difficulty=
// and ?area= parameters.
func (h *QuestionHandler) Search(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	q := r.URL.Query()
	difficulty, area, err := parseSearchFilters(q)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.Search(token, difficulty, area)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

// Get returns the pooled question identified by the {id} path segment. Open to any
// authenticated user; the response includes the answer.
func (h *QuestionHandler) Get(w http.ResponseWriter, r *http.Request) {
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
	data, status, err := h.svc.Get(token, uint(id))
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

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
