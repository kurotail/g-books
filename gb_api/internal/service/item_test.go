package service

import (
	"encoding/json"
	"net/http"
	"testing"
)

type mockItemRepo struct {
	inv  map[uint]uint
	slot map[uint]uint
}

func newMockItemRepo() *mockItemRepo {
	return &mockItemRepo{
		inv:  map[uint]uint{1: 3, 2: 1},
		slot: map[uint]uint{0: 1, 2: 2},
	}
}

func (m *mockItemRepo) QueryInv(_ uint) (map[uint]uint, error) {
	result := make(map[uint]uint, len(m.inv))
	for k, v := range m.inv {
		result[k] = v
	}
	return result, nil
}

func (m *mockItemRepo) QuerySlot(_ uint) (map[uint]uint, error) {
	result := make(map[uint]uint, len(m.slot))
	for k, v := range m.slot {
		result[k] = v
	}
	return result, nil
}

func (m *mockItemRepo) SetInv(_, itemID, itemCount uint) error {
	if itemCount == 0 {
		delete(m.inv, itemID)
	} else {
		m.inv[itemID] = itemCount
	}
	return nil
}

func (m *mockItemRepo) SetSlot(_, slotID, itemID uint) error {
	if itemID == 0 {
		delete(m.slot, slotID)
	} else {
		m.slot[slotID] = itemID
	}
	return nil
}

func validAccessToken(t *testing.T) string {
	t.Helper()
	tok, err := newTestAuthSvc().newAccessToken("testuser")
	if err != nil {
		t.Fatalf("failed to mint access token: %v", err)
	}
	return tok
}

func newItemSvc(t *testing.T) (*ItemSvc, *mockItemRepo) {
	t.Helper()
	r := newMockItemRepo()
	return NewItemSvc(r), r
}

// --- QueryInv ---

func TestItemSvc_QueryInv_ValidToken(t *testing.T) {
	useAdvancingClock(t)
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
	useAdvancingClock(t)
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

// --- DeleteSlotItem ---

func TestItemSvc_DeleteSlotItem_RemovesSlot(t *testing.T) {
	useAdvancingClock(t)
	s, r := newItemSvc(t)

	status, err := s.DeleteSlotItem(validAccessToken(t), 0, 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if _, ok := r.slot[0]; ok {
		t.Error("expected slot 0 to be removed")
	}
}

func TestItemSvc_DeleteSlotItem_InvalidToken(t *testing.T) {
	s, _ := newItemSvc(t)
	status, err := s.DeleteSlotItem("bad.token", 0, 0)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

// --- IncreaseInvItem ---

func TestItemSvc_IncreaseInvItem_ExistingItem(t *testing.T) {
	useAdvancingClock(t)
	s, r := newItemSvc(t)

	status, err := s.IncreaseInvItem(validAccessToken(t), 0, 1, 2)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if r.inv[1] != 5 {
		t.Errorf("expected inv[1]==5, got %d", r.inv[1])
	}
}

func TestItemSvc_IncreaseInvItem_NewItem(t *testing.T) {
	useAdvancingClock(t)
	s, r := newItemSvc(t)

	status, err := s.IncreaseInvItem(validAccessToken(t), 0, 99, 1)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if r.inv[99] != 1 {
		t.Errorf("expected inv[99]==1, got %d", r.inv[99])
	}
}

func TestItemSvc_IncreaseInvItem_InvalidToken(t *testing.T) {
	s, _ := newItemSvc(t)
	status, err := s.IncreaseInvItem("bad.token", 0, 1, 1)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

// --- TranInv2Slot ---

func TestItemSvc_TranInv2Slot_DecrementsInvAndSetsSlot(t *testing.T) {
	useAdvancingClock(t)
	s, r := newItemSvc(t)

	status, err := s.TranInv2Slot(validAccessToken(t), 0, 1, 5)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if r.inv[1] != 2 {
		t.Errorf("expected inv[1]==2, got %d", r.inv[1])
	}
	if r.slot[5] != 1 {
		t.Errorf("expected slot[5]==1, got %d", r.slot[5])
	}
}

func TestItemSvc_TranInv2Slot_OutOfStock(t *testing.T) {
	useAdvancingClock(t)
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
	useAdvancingClock(t)
	s, r := newItemSvc(t)

	status, err := s.TranSlot2Inv(validAccessToken(t), 0, 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if _, ok := r.slot[0]; ok {
		t.Error("expected slot 0 to be cleared")
	}
	if r.inv[1] != 4 {
		t.Errorf("expected inv[1]==4, got %d", r.inv[1])
	}
}

func TestItemSvc_TranSlot2Inv_NonExistentSlot(t *testing.T) {
	useAdvancingClock(t)
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
