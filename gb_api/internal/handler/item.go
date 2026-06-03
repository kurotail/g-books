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

func decodeItemOp(r *http.Request) (model.ItemOperation, error) {
	var op model.ItemOperation
	return op, json.NewDecoder(r.Body).Decode(&op)
}

func (h *ItemHandler) QueryInv(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	op, err := decodeItemOp(r)
	if err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.QueryInv(token, op.GroupID)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

func (h *ItemHandler) QuerySlot(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	op, err := decodeItemOp(r)
	if err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.QuerySlot(token, op.GroupID)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

func (h *ItemHandler) DeleteSlotItem(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	op, err := decodeItemOp(r)
	if err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	if op.SlotID == nil {
		http.Error(w, "缺少 slot_id", http.StatusBadRequest)
		return
	}
	status, err := h.svc.DeleteSlotItem(token, op.GroupID, *op.SlotID)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	w.WriteHeader(status)
}

func (h *ItemHandler) IncreaseInvItem(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	op, err := decodeItemOp(r)
	if err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	if op.ItemID == nil || op.ItemCount == nil {
		http.Error(w, "缺少 item_id 或 item_count", http.StatusBadRequest)
		return
	}
	status, err := h.svc.IncreaseInvItem(token, op.GroupID, *op.ItemID, *op.ItemCount)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	w.WriteHeader(status)
}

func (h *ItemHandler) TranInv2Slot(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	op, err := decodeItemOp(r)
	if err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	if op.ItemID == nil || op.SlotID == nil {
		http.Error(w, "缺少 item_id 或 slot_id", http.StatusBadRequest)
		return
	}
	status, err := h.svc.TranInv2Slot(token, op.GroupID, *op.ItemID, *op.SlotID)
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
	op, err := decodeItemOp(r)
	if err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	if op.SlotID == nil {
		http.Error(w, "缺少 slot_id", http.StatusBadRequest)
		return
	}
	status, err := h.svc.TranSlot2Inv(token, op.GroupID, *op.SlotID)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	w.WriteHeader(status)
}
