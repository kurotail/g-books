package handler

import (
	"encoding/json"
	"net/http"
	"strconv"

	"gb-api/internal/model"
	"gb-api/internal/service"
)

type BuildingHandler struct {
	svc *service.BuildingSvc
}

func NewBuildingHandler(s *service.BuildingSvc) *BuildingHandler {
	return &BuildingHandler{svc: s}
}

// Create defines a new building (teacher/admin only).
func (h *BuildingHandler) Create(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.CreateBuildingRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	if req.Name == "" {
		http.Error(w, "缺少 name", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.Create(token, req.Name, req.Layout, req.TypeAllowedSlot, req.DifficultyType)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

// Get returns the building identified by the {id} path segment.
func (h *BuildingHandler) Get(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	id, err := strconv.ParseUint(r.PathValue("id"), 10, 64)
	if err != nil {
		http.Error(w, "不合法的 building id", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.Get(token, uint(id))
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

// List returns every building.
func (h *BuildingHandler) List(w http.ResponseWriter, r *http.Request) {
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
