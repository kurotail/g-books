package handler

import (
	"encoding/json"
	"net/http"

	"gb-api/internal/model"
	"gb-api/internal/service"
)

type GroupHandler struct {
	svc *service.GroupSvc
}

func NewGroupHandler(s *service.GroupSvc) *GroupHandler {
	return &GroupHandler{svc: s}
}

func (h *GroupHandler) SetGroup(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.SetGroupRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	if req.Username == "" {
		http.Error(w, "缺少 username", http.StatusBadRequest)
		return
	}
	if req.GroupID == nil {
		http.Error(w, "缺少 group_id", http.StatusBadRequest)
		return
	}
	status, err := h.svc.SetGroup(token, req.Username, *req.GroupID)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	w.WriteHeader(status)
}

func (h *GroupHandler) SetName(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.SetGroupNameRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	if req.GroupID == nil {
		http.Error(w, "缺少 group_id", http.StatusBadRequest)
		return
	}
	if *req.GroupID == 0 {
		http.Error(w, "group_id 必須大於 0", http.StatusBadRequest)
		return
	}
	if req.Name == "" {
		http.Error(w, "缺少 name", http.StatusBadRequest)
		return
	}
	status, err := h.svc.SetName(token, *req.GroupID, req.Name)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	w.WriteHeader(status)
}

func (h *GroupHandler) SetBuilding(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.SetBuildingRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	if req.GroupID == nil {
		http.Error(w, "缺少 group_id", http.StatusBadRequest)
		return
	}
	if *req.GroupID == 0 {
		http.Error(w, "group_id 必須大於 0", http.StatusBadRequest)
		return
	}
	if req.BuildingID == nil {
		http.Error(w, "缺少 building_id", http.StatusBadRequest)
		return
	}
	status, err := h.svc.SetBuilding(token, *req.GroupID, *req.BuildingID)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	w.WriteHeader(status)
}

func (h *GroupHandler) QueryGroup(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	data, status, err := h.svc.QueryGroup(token)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

func (h *GroupHandler) QueryMember(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.QueryMemberRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	if req.GroupID == nil {
		http.Error(w, "缺少 group_id", http.StatusBadRequest)
		return
	}
	if *req.GroupID == 0 {
		http.Error(w, "group_id 必須大於 0", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.QueryMember(token, *req.GroupID)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}
