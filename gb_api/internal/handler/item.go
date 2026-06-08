package handler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"gb-api/internal/model"
	"gb-api/internal/service"
)

type ItemHandler struct {
	svc *service.ItemSvc
}

func NewItemHandler(s *service.ItemSvc) *ItemHandler {
	return &ItemHandler{svc: s}
}

func bearerToken(r *http.Request) (string, error) {
	parts := strings.SplitN(r.Header.Get("Authorization"), " ", 2)
	if len(parts) != 2 || parts[0] != "Bearer" || parts[1] == "" {
		return "", fmt.Errorf("Authorization Header 格式必須為 Bearer <Token>")
	}
	return parts[1], nil
}

// QueryItems returns all of a group's items — its inventory and its slots.
func (h *ItemHandler) QueryItems(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.QueryItemRequest
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
	data, status, err := h.svc.QueryItems(token, *req.GroupID)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

func (h *ItemHandler) TranInv2Slot(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.TranInv2SlotRequest
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
	if req.ItemID == nil {
		http.Error(w, "缺少 item_id", http.StatusBadRequest)
		return
	}
	if req.SlotID == nil {
		http.Error(w, "缺少 slot_id", http.StatusBadRequest)
		return
	}
	if *req.ItemID == 0 {
		http.Error(w, "item_id 必須大於 0", http.StatusBadRequest)
		return
	}
	status, err := h.svc.TranInv2Slot(token, *req.GroupID, *req.ItemID, *req.SlotID)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	w.WriteHeader(status)
}

func (h *ItemHandler) TranSlot2Inv(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.TranSlot2InvRequest
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
	if req.SlotID == nil {
		http.Error(w, "缺少 slot_id", http.StatusBadRequest)
		return
	}
	status, err := h.svc.TranSlot2Inv(token, *req.GroupID, *req.SlotID)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	w.WriteHeader(status)
}
