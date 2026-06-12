package service

import (
	"encoding/json"
	"net/http"
	"testing"

	"gb-api/internal/model"
	"gb-api/internal/repo/mock"
)

func validAccessToken(t *testing.T) string {
	t.Helper()
	tok, err := newTestAuthSvc().newAccessToken("testuser")
	if err != nil {
		t.Fatalf("failed to mint access token: %v", err)
	}
	return tok
}

func allowAll() map[uint][]uint {
	return map[uint][]uint{10: {0, 1, 2, 5}, 20: {0, 1, 2, 5}, 30: {0, 1, 2, 5}}
}

func itemSvc(role, group uint, allowed map[uint][]uint) (*ItemSvc, *mock.ItemRepo) {
	r := &mock.ItemRepo{
		Inv:  map[uint]struct{}{1: {}, 2: {}},
		Slot: map[uint]int{0: 3},
		Items: map[uint]model.Item{
			1: {ItemID: 1, Type: 10, QuestionID: 1},
			2: {ItemID: 2, Type: 20, QuestionID: 2},
			3: {ItemID: 3, Type: 10},
		},
	}
	users := &mock.AuthRepo{
		Roles:  map[string]uint{"testuser": role},
		Groups: map[string]uint{"testuser": group},
	}
	groups := &mock.GroupRepo{BuildingIDs: map[uint]uint{group: 1}}
	buildings := &mock.BuildingRepo{Buildings: map[uint]model.Building{1: {ID: 1, TypeAllowedSlot: allowed}}}
	return NewItemSvc(r, users, groups, buildings), r
}

func newItemSvc(t *testing.T) (*ItemSvc, *mock.ItemRepo) {
	t.Helper()
	// "testuser" (the subject of validAccessToken) is a teacher, so QUIZ-state
	// blocking never applies to the baseline tests.
	return itemSvc(model.RoleTeacher, 0, allowAll())
}

// newItemSvcAs builds an ItemSvc whose caller "testuser" has the given role and group.
func newItemSvcAs(role, group uint) (*ItemSvc, *mock.ItemRepo) {
	return itemSvc(role, group, allowAll())
}

func findItem(views []model.ItemView, id uint) (model.ItemView, bool) {
	for _, v := range views {
		if v.ItemID == id {
			return v, true
		}
	}
	return model.ItemView{}, false
}

// --- QueryItems ---

func TestItemSvc_QueryItems_TeacherSeesFullFields(t *testing.T) {
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
	if len(resp.Inventory) != 2 {
		t.Fatalf("expected 2 inventory items, got %d (%+v)", len(resp.Inventory), resp.Inventory)
	}
	one, ok := findItem(resp.Inventory, 1)
	if !ok || one.Type != 10 || one.QuestionID != 1 {
		t.Errorf("expected item 1 {type 10, q 1}, got %+v (found=%v)", one, ok)
	}
	slot := resp.Slots[0]
	if slot.ItemID != 3 || slot.Type != 10 || slot.Broken {
		t.Errorf("expected slot 0 to hold normal item 3 type 10, got %+v", slot)
	}
}

func TestItemSvc_QueryItems_StudentOwnGroupFull_OtherGroupTypeOnly(t *testing.T) {
	s, _ := newItemSvcAs(model.RoleStudent, 5)

	// Own group (5): full fields.
	data, _, err := s.QueryItems(validAccessToken(t), 5)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	var own model.ItemsResponse
	json.Unmarshal(data, &own)
	if one, ok := findItem(own.Inventory, 1); !ok || one.Type != 10 || one.QuestionID != 1 {
		t.Errorf("own group: expected full item 1, got %+v (found=%v)", one, ok)
	}

	// Other group (0): type only — no item_id / question_id.
	data, _, err = s.QueryItems(validAccessToken(t), 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	var other model.ItemsResponse
	json.Unmarshal(data, &other)
	if len(other.Inventory) != 2 {
		t.Fatalf("other group: expected 2 items, got %d", len(other.Inventory))
	}
	for _, v := range other.Inventory {
		if v.ItemID != 0 || v.QuestionID != 0 {
			t.Errorf("other group: expected type-only view, got %+v", v)
		}
		if v.Type == 0 {
			t.Errorf("other group: expected a type, got %+v", v)
		}
	}
	if sv := other.Slots[0]; sv.ItemID != 0 || sv.QuestionID != 0 || sv.Type != 10 {
		t.Errorf("other group: expected type-only slot view, got %+v", sv)
	}
}

func TestItemSvc_QueryItems_GroupZeroIsNeverOwnGroup(t *testing.T) {
	// A student with no group (GroupID 0) querying group 0 ("no group") must get
	// the restricted, type-only view — group 0 is never anyone's own group.
	s, _ := newItemSvcAs(model.RoleStudent, 0)

	data, _, err := s.QueryItems(validAccessToken(t), 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	var resp model.ItemsResponse
	json.Unmarshal(data, &resp)
	if len(resp.Inventory) == 0 {
		t.Fatal("expected items to project against")
	}
	for _, v := range resp.Inventory {
		if v.ItemID != 0 || v.QuestionID != 0 {
			t.Errorf("group 0 must be a restricted (type-only) view, got %+v", v)
		}
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

func TestItemSvc_TranInv2Slot_MovesItemToSlot(t *testing.T) {
	s, r := itemSvc(model.RoleTeacher, 5, allowAll())

	status, err := s.TranInv2Slot(validAccessToken(t), 5, 1, 5)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if _, ok := r.Inv[1]; ok {
		t.Error("expected item 1 to leave the inventory set")
	}
	if r.Slot[5] != 1 {
		t.Errorf("expected slot[5]==1, got %d", r.Slot[5])
	}
}

func TestItemSvc_TranInv2Slot_ItemNotInInventory(t *testing.T) {
	s, _ := itemSvc(model.RoleTeacher, 5, allowAll())

	status, err := s.TranInv2Slot(validAccessToken(t), 5, 99, 5)
	if err == nil {
		t.Fatal("expected error for an item the group does not own")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestItemSvc_TranInv2Slot_TypeNotAllowed(t *testing.T) {
	// building allows type 10 only in slot 1
	s, r := itemSvc(model.RoleTeacher, 5, map[uint][]uint{10: {1}})

	status, err := s.TranInv2Slot(validAccessToken(t), 5, 1, 2) // item 1 is type 10, slot 2
	if err == nil {
		t.Fatal("expected error: type not allowed in slot")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
	if _, ok := r.Inv[1]; !ok {
		t.Error("rejected move must leave the item in inventory")
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
	s, r := itemSvc(model.RoleTeacher, 5, allowAll())

	// slot 0 already holds normal item 3; moving item 1 in should swap item 3
	// back into the inventory set.
	status, err := s.TranInv2Slot(validAccessToken(t), 5, 1, 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if r.Slot[0] != 1 {
		t.Errorf("expected slot[0]==1, got %d", r.Slot[0])
	}
	if _, ok := r.Inv[1]; ok {
		t.Error("expected item 1 to leave inventory")
	}
	if _, ok := r.Inv[3]; !ok {
		t.Error("expected item 3 to be swapped back into inventory")
	}
}

func TestItemSvc_TranInv2Slot_BrokenSlotRejected(t *testing.T) {
	s, r := itemSvc(model.RoleTeacher, 5, allowAll())
	r.Slot[2] = -3 // slot 2 holds a broken item 3

	status, err := s.TranInv2Slot(validAccessToken(t), 5, 1, 2)
	if err == nil {
		t.Fatal("expected error placing into a broken slot")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
	if r.Slot[2] != -3 {
		t.Errorf("expected slot[2] unchanged (-3), got %d", r.Slot[2])
	}
	if _, ok := r.Inv[1]; !ok {
		t.Error("expected item 1 unchanged in inventory")
	}
}

func TestItemSvc_TranInv2Slot_StudentBlockedInQuiz(t *testing.T) {
	s, _ := newItemSvcAs(model.RoleStudent, 0)

	setState(model.StateQuiz2)
	defer setState(model.StateNormal)

	status, err := s.TranInv2Slot(validAccessToken(t), 0, 1, 5)
	if err == nil {
		t.Fatal("expected error for student during QUIZ")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestItemSvc_TranInv2Slot_StudentInGroupAllowed(t *testing.T) {
	s, r := newItemSvcAs(model.RoleStudent, 5)

	status, err := s.TranInv2Slot(validAccessToken(t), 5, 1, 5)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if r.Slot[5] != 1 {
		t.Errorf("expected slot[5]==1, got %d", r.Slot[5])
	}
}

func TestItemSvc_TranInv2Slot_StudentOtherGroupForbidden(t *testing.T) {
	// Student belongs to group 5 but tries to operate on group 0.
	s, _ := newItemSvcAs(model.RoleStudent, 5)

	status, err := s.TranInv2Slot(validAccessToken(t), 0, 1, 5)
	if err == nil {
		t.Fatal("expected error for student operating on another group")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestItemSvc_TranInv2Slot_TeacherOtherGroupForbidden(t *testing.T) {
	// The own-group rule is universal: even a teacher may only operate on the
	// group they belong to. Here the teacher belongs to group 5 but targets group 6.
	s, _ := itemSvc(model.RoleTeacher, 5, allowAll())

	status, err := s.TranInv2Slot(validAccessToken(t), 6, 1, 5)
	if err == nil {
		t.Fatal("expected error for a caller operating on another group")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

// --- TranSlot2Inv ---

func TestItemSvc_TranSlot2Inv_ClearsSlotAndAddsToInv(t *testing.T) {
	s, r := itemSvc(model.RoleTeacher, 5, allowAll())

	status, err := s.TranSlot2Inv(validAccessToken(t), 5, 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if _, ok := r.Slot[0]; ok {
		t.Error("expected slot 0 to be cleared")
	}
	if _, ok := r.Inv[3]; !ok {
		t.Error("expected item 3 to return to the inventory set")
	}
}

func TestItemSvc_TranSlot2Inv_NonExistentSlot(t *testing.T) {
	s, _ := itemSvc(model.RoleTeacher, 5, allowAll())

	status, err := s.TranSlot2Inv(validAccessToken(t), 5, 99)
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
	s, r := itemSvc(model.RoleTeacher, 5, allowAll())
	r.Slot[2] = -3 // broken item 3

	status, err := s.TranSlot2Inv(validAccessToken(t), 5, 2)
	if err == nil {
		t.Fatal("expected error returning a broken item")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestItemSvc_TranSlot2Inv_StudentInGroupAllowed(t *testing.T) {
	s, r := newItemSvcAs(model.RoleStudent, 5)

	status, err := s.TranSlot2Inv(validAccessToken(t), 5, 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if _, ok := r.Inv[3]; !ok {
		t.Error("expected item 3 to return to the inventory set")
	}
}

func TestItemSvc_TranSlot2Inv_StudentOtherGroupForbidden(t *testing.T) {
	s, _ := newItemSvcAs(model.RoleStudent, 5)

	status, err := s.TranSlot2Inv(validAccessToken(t), 0, 0)
	if err == nil {
		t.Fatal("expected error for student operating on another group")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestItemSvc_TranSlot2Inv_StudentBlockedInQuiz(t *testing.T) {
	s, _ := newItemSvcAs(model.RoleStudent, 0)

	setState(model.StateQuiz2)
	defer setState(model.StateNormal)

	status, err := s.TranSlot2Inv(validAccessToken(t), 0, 0)
	if err == nil {
		t.Fatal("expected error for student during QUIZ")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}
