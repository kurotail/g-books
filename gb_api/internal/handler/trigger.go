package handler

import (
	"encoding/json"
	"net/http"

	"gb-api/internal/model"
	"gb-api/internal/service"
)

type TriggerHandler struct {
	svc *service.TriggerSvc
}

func NewTriggerHandler(s *service.TriggerSvc) *TriggerHandler {
	return &TriggerHandler{svc: s}
}

// GenerateItem issues an item-earning session (QUIZ1 state).
func (h *TriggerHandler) GenerateItem(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.GenerateItemRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	if req.Difficulty == nil {
		http.Error(w, "缺少 difficulty", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.GenerateItem(token, *req.Difficulty)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

// GenerateTarget issues an attack/repair session against a user's slot (QUIZ2 state).
func (h *TriggerHandler) GenerateTarget(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.GenerateTargetRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	if req.TargetUserID == nil || *req.TargetUserID == 0 {
		http.Error(w, "缺少 target_user_id", http.StatusBadRequest)
		return
	}
	if req.TargetSlotID == nil {
		http.Error(w, "缺少 target_slot_id", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.GenerateTarget(token, *req.TargetUserID, *req.TargetSlotID)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

func (h *TriggerHandler) Answer(w http.ResponseWriter, r *http.Request) {
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
	if len(req.Answer) == 0 {
		http.Error(w, "缺少 answer", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.Answer(token, req.Session, req.Answer)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}
