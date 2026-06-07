package service

import (
	"encoding/json"
	"net/http"
	"testing"

	"gb-api/internal/model"
	"gb-api/internal/repo/mock"
)

func newMockItemRepo() *mock.ItemRepo {
	return &mock.ItemRepo{
		Inv:  map[uint]uint{1: 3, 2: 1},
		Slot: map[uint]int{0: 1, 2: 2},
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
	// "testuser" (the subject of validAccessToken) is a teacher, so QUIZ-state
	// blocking never applies to the baseline tests.
	users := &mock.AuthRepo{Roles: map[string]uint{"testuser": model.RoleTeacher}}
	return NewItemSvc(r, users), r
}

// --- QueryItems ---

func TestItemSvc_QueryItems_ValidToken(t *testing.T) {
	s, _ := newItemSvc(t)

	data, status, err := s.QueryItems(validAccessToken(t), 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var resp model.ItemsResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if resp.GroupID != 0 {
		t.Errorf("expected group_id 0, got %d", resp.GroupID)
	}
	if resp.Inventory[1] != 3 {
		t.Errorf("expected inv[1]==3, got %d", resp.Inventory[1])
	}
	if resp.Inventory[2] != 1 {
		t.Errorf("expected inv[2]==1, got %d", resp.Inventory[2])
	}
	if resp.Slots[0] != 1 {
		t.Errorf("expected slot[0]==1, got %d", resp.Slots[0])
	}
	if resp.Slots[2] != 2 {
		t.Errorf("expected slot[2]==2, got %d", resp.Slots[2])
	}
}

func TestItemSvc_QueryItems_InvalidToken(t *testing.T) {
	s, _ := newItemSvc(t)
	_, status, err := s.QueryItems("invalid.token", 0)
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

func TestItemSvc_TranInv2Slot_SwapNormalItem(t *testing.T) {
	s, r := newItemSvc(t)

	// slot 2 already holds normal item 2; moving item 1 in should swap item 2
	// back to the inventory.
	status, err := s.TranInv2Slot(validAccessToken(t), 0, 1, 2)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if r.Slot[2] != 1 {
		t.Errorf("expected slot[2]==1, got %d", r.Slot[2])
	}
	if r.Inv[1] != 2 {
		t.Errorf("expected inv[1]==2 (placed one), got %d", r.Inv[1])
	}
	if r.Inv[2] != 2 {
		t.Errorf("expected inv[2]==2 (swapped back), got %d", r.Inv[2])
	}
}

func TestItemSvc_TranInv2Slot_BrokenSlotRejected(t *testing.T) {
	s, r := newItemSvc(t)
	r.Slot[2] = -3 // slot 2 holds a broken item 3

	status, err := s.TranInv2Slot(validAccessToken(t), 0, 1, 2)
	if err == nil {
		t.Fatal("expected error placing into a broken slot")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
	// nothing should have changed.
	if r.Slot[2] != -3 {
		t.Errorf("expected slot[2] unchanged (-3), got %d", r.Slot[2])
	}
	if r.Inv[1] != 3 {
		t.Errorf("expected inv[1] unchanged (3), got %d", r.Inv[1])
	}
}

func TestItemSvc_TranInv2Slot_StudentBlockedInQuiz(t *testing.T) {
	r := newMockItemRepo()
	users := &mock.AuthRepo{Roles: map[string]uint{"testuser": model.RoleStudent}}
	s := NewItemSvc(r, users)

	setState(model.StateQuiz)
	defer setState(model.StateNormal)

	status, err := s.TranInv2Slot(validAccessToken(t), 0, 1, 5)
	if err == nil {
		t.Fatal("expected error for student during QUIZ")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
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

func TestItemSvc_TranSlot2Inv_BrokenSlotRejected(t *testing.T) {
	s, r := newItemSvc(t)
	r.Slot[2] = -3 // broken item 3

	status, err := s.TranSlot2Inv(validAccessToken(t), 0, 2)
	if err == nil {
		t.Fatal("expected error returning a broken item")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestItemSvc_TranSlot2Inv_StudentBlockedInQuiz(t *testing.T) {
	r := newMockItemRepo()
	users := &mock.AuthRepo{Roles: map[string]uint{"testuser": model.RoleStudent}}
	s := NewItemSvc(r, users)

	setState(model.StateQuiz)
	defer setState(model.StateNormal)

	status, err := s.TranSlot2Inv(validAccessToken(t), 0, 0)
	if err == nil {
		t.Fatal("expected error for student during QUIZ")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}
