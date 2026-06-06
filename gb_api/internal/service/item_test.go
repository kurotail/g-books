package service

import (
	"encoding/json"
	"net/http"
	"testing"

	"gb-api/internal/repo/mock"
)

func newMockItemRepo() *mock.ItemRepo {
	return &mock.ItemRepo{
		Inv:  map[uint]uint{1: 3, 2: 1},
		Slot: map[uint]uint{0: 1, 2: 2},
	}
}

func validAccessToken(t *testing.T) string {
	t.Helper()
	tok, err := newTestAuthSvc().newAccessToken("testuser")
	if err != nil {
		t.Fatalf("failed to mint access token: %v", err)
	}
	return tok
}

func newItemSvc(t *testing.T) (*ItemSvc, *mock.ItemRepo) {
	t.Helper()
	r := newMockItemRepo()
	return NewItemSvc(r), r
}

// --- QueryInv ---

func TestItemSvc_QueryInv_ValidToken(t *testing.T) {
	s, _ := newItemSvc(t)

	data, status, err := s.QueryInv(validAccessToken(t), 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var inv map[string]uint
	if err := json.Unmarshal(data, &inv); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if inv["1"] != 3 {
		t.Errorf("expected inv[1]==3, got %d", inv["1"])
	}
	if inv["2"] != 1 {
		t.Errorf("expected inv[2]==1, got %d", inv["2"])
	}
}

func TestItemSvc_QueryInv_InvalidToken(t *testing.T) {
	s, _ := newItemSvc(t)
	_, status, err := s.QueryInv("invalid.token", 0)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

// --- QuerySlot ---

func TestItemSvc_QuerySlot_ValidToken(t *testing.T) {
	s, _ := newItemSvc(t)

	data, status, err := s.QuerySlot(validAccessToken(t), 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var slot map[string]uint
	if err := json.Unmarshal(data, &slot); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if slot["0"] != 1 {
		t.Errorf("expected slot[0]==1, got %d", slot["0"])
	}
	if slot["2"] != 2 {
		t.Errorf("expected slot[2]==2, got %d", slot["2"])
	}
}

func TestItemSvc_QuerySlot_InvalidToken(t *testing.T) {
	s, _ := newItemSvc(t)
	_, status, err := s.QuerySlot("invalid.token", 0)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

// --- TranInv2Slot ---

func TestItemSvc_TranInv2Slot_DecrementsInvAndSetsSlot(t *testing.T) {
	s, r := newItemSvc(t)

	status, err := s.TranInv2Slot(validAccessToken(t), 0, 1, 5)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if r.Inv[1] != 2 {
		t.Errorf("expected inv[1]==2, got %d", r.Inv[1])
	}
	if r.Slot[5] != 1 {
		t.Errorf("expected slot[5]==1, got %d", r.Slot[5])
	}
}

func TestItemSvc_TranInv2Slot_OutOfStock(t *testing.T) {
	s, _ := newItemSvc(t)

	status, err := s.TranInv2Slot(validAccessToken(t), 0, 99, 5)
	if err == nil {
		t.Fatal("expected error for out-of-stock item")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestItemSvc_TranInv2Slot_InvalidToken(t *testing.T) {
	s, _ := newItemSvc(t)
	status, err := s.TranInv2Slot("bad.token", 0, 1, 5)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

// --- TranSlot2Inv ---

func TestItemSvc_TranSlot2Inv_ClearsSlotAndIncrementsInv(t *testing.T) {
	s, r := newItemSvc(t)

	status, err := s.TranSlot2Inv(validAccessToken(t), 0, 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if _, ok := r.Slot[0]; ok {
		t.Error("expected slot 0 to be cleared")
	}
	if r.Inv[1] != 4 {
		t.Errorf("expected inv[1]==4, got %d", r.Inv[1])
	}
}

func TestItemSvc_TranSlot2Inv_NonExistentSlot(t *testing.T) {
	s, _ := newItemSvc(t)

	status, err := s.TranSlot2Inv(validAccessToken(t), 0, 99)
	if err == nil {
		t.Fatal("expected error for non-existent slot")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestItemSvc_TranSlot2Inv_InvalidToken(t *testing.T) {
	s, _ := newItemSvc(t)
	status, err := s.TranSlot2Inv("bad.token", 0, 0)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}
