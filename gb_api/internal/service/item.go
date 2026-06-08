package service

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"

	apperr "gb-api/internal/error"
	"gb-api/internal/model"
	"gb-api/internal/repo"
)

type ItemSvc struct {
	repo      repo.ItemRepo
	users     repo.UserRepo
	groups    repo.GroupRepo
	buildings repo.BuildingRepo
}

func NewItemSvc(r repo.ItemRepo, users repo.UserRepo, groups repo.GroupRepo, buildings repo.BuildingRepo) *ItemSvc {
	return &ItemSvc{repo: r, users: users, groups: groups, buildings: buildings}
}

// ownsItem reports whether the group holds itemID loose in its inventory.
func (s *ItemSvc) ownsItem(groupID, itemID uint) (bool, error) {
	ids, err := s.repo.QueryInv(groupID)
	if err != nil {
		return false, err
	}
	for _, id := range ids {
		if id == itemID {
			return true, nil
		}
	}
	return false, nil
}

// slotAllowsType reports whether the group's building permits an item of itemType
// in slotID (per the building's TypeAllowedSlot). A group with no building, or a
// building that no longer exists, allows nothing.
func (s *ItemSvc) slotAllowsType(groupID, slotID, itemType uint) (bool, error) {
	g, err := s.groups.GetGroup(groupID)
	if err != nil {
		return false, err
	}
	if g.BuildingID == 0 {
		return false, nil
	}
	b, err := s.buildings.GetBuilding(g.BuildingID)
	if err != nil {
		if errors.Is(err, apperr.ErrBuildingNotFound) {
			return false, nil
		}
		return false, err
	}
	for _, allowed := range b.TypeAllowedSlot[itemType] {
		if allowed == slotID {
			return true, nil
		}
	}
	return false, nil
}

// blockStudentDuringQuiz returns a non-nil error (with an HTTP status) when the
// caller is a student and the server is in QUIZ state, in which inventory moves
// are disabled for students.
func (s *ItemSvc) blockStudentDuringQuiz(accessToken string) (int, error) {
	claims, err := validateAccessToken(accessToken)
	if err != nil {
		return http.StatusUnauthorized, err
	}
	caller, err := s.users.GetUser(claims.Username)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if studentBlockedDuringQuiz(caller.Role) {
		return http.StatusForbidden, fmt.Errorf("QUIZ 狀態下學生無法移動物品")
	}
	return http.StatusOK, nil
}

func (s *ItemSvc) QueryItems(accessToken string, groupID uint) ([]byte, int, error) {
	claims, err := validateAccessToken(accessToken)
	if err != nil {
		return nil, http.StatusUnauthorized, err
	}
	caller, err := s.users.GetUser(claims.Username)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	// group 0 means "no group", so it is never anyone's own group.
	full := caller.Role >= model.RoleTeacher || (groupID != 0 && caller.GroupID == groupID)

	invIDs, err := s.repo.QueryInv(groupID)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	inventory := make([]model.ItemView, 0, len(invIDs))
	for _, id := range invIDs {
		it, _, err := s.repo.GetItem(id)
		if err != nil {
			return nil, http.StatusInternalServerError, err
		}
		if full {
			inventory = append(inventory, model.ItemView{ItemID: it.ItemID, Type: it.Type, QuestionID: it.QuestionID})
		} else {
			inventory = append(inventory, model.ItemView{Type: it.Type})
		}
	}

	slotMap, err := s.repo.QuerySlot(groupID)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	slots := make(map[uint]model.SlotView, len(slotMap))
	for slotID, signed := range slotMap {
		if signed == 0 {
			continue
		}
		broken := signed < 0
		itemID := uint(signed)
		if broken {
			itemID = uint(-signed)
		}
		it, _, err := s.repo.GetItem(itemID)
		if err != nil {
			return nil, http.StatusInternalServerError, err
		}
		slots[slotID] = slotView(it, broken, full)
	}

	data, err := json.Marshal(model.ItemsResponse{GroupID: groupID, Inventory: inventory, Slots: slots})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func itemView(it model.Item, full bool) model.ItemView {
	if !full {
		return model.ItemView{Type: it.Type}
	}
	return model.ItemView{ItemID: it.ItemID, Type: it.Type, QuestionID: it.QuestionID}
}

func slotView(it model.Item, broken, full bool) model.SlotView {
	if !full {
		return model.SlotView{Type: it.Type, Broken: broken}
	}
	return model.SlotView{ItemID: it.ItemID, Type: it.Type, QuestionID: it.QuestionID, Broken: broken}
}

// TranInv2Slot moves an owned item from the group's inventory into a slot. The
// item's Type must be allowed in the slot by the group's building. A normal item
// already in the slot is swapped back into the inventory; a broken one blocks the move.
func (s *ItemSvc) TranInv2Slot(accessToken string, groupID, itemID, slotID uint) (int, error) {
	if status, err := s.blockStudentDuringQuiz(accessToken); err != nil {
		return status, err
	}
	has, err := s.ownsItem(groupID, itemID)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if !has {
		return http.StatusBadRequest, fmt.Errorf("item %d 不在庫存中", itemID)
	}
	it, ok, err := s.repo.GetItem(itemID)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if !ok {
		return http.StatusInternalServerError, fmt.Errorf("item %d 不存在", itemID)
	}
	allowed, err := s.slotAllowsType(groupID, slotID, it.Type)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if !allowed {
		return http.StatusBadRequest, fmt.Errorf("slot %d 不允許類型 %d 的物品", slotID, it.Type)
	}
	slot, err := s.repo.QuerySlot(groupID)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	held := slot[slotID]
	if held < 0 {
		return http.StatusBadRequest, fmt.Errorf("slot %d (item %d) 已損毀，無法放置物品", slotID, -held)
	}
	if held > 0 {
		if err := s.repo.AddInvItem(groupID, uint(held)); err != nil {
			return http.StatusInternalServerError, err
		}
	}
	if err := s.repo.RemoveInvItem(groupID, itemID); err != nil {
		return http.StatusInternalServerError, err
	}
	if err := s.repo.SetSlot(groupID, slotID, int(itemID)); err != nil {
		return http.StatusInternalServerError, err
	}
	return http.StatusOK, nil
}

// TranSlot2Inv returns the item held in a slot to the group's inventory. Only a
// normal (non-broken) item can be returned.
func (s *ItemSvc) TranSlot2Inv(accessToken string, groupID, slotID uint) (int, error) {
	if status, err := s.blockStudentDuringQuiz(accessToken); err != nil {
		return status, err
	}
	slot, err := s.repo.QuerySlot(groupID)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	itemID, ok := slot[slotID]
	if !ok || itemID == 0 {
		return http.StatusBadRequest, fmt.Errorf("slot %d 沒有物品", slotID)
	}
	if itemID < 0 {
		return http.StatusBadRequest, fmt.Errorf("slot %d (item %d) 已損毀", slotID, -itemID)
	}
	if err := s.repo.AddInvItem(groupID, uint(itemID)); err != nil {
		return http.StatusInternalServerError, err
	}
	if err := s.repo.SetSlot(groupID, slotID, 0); err != nil {
		return http.StatusInternalServerError, err
	}
	return http.StatusOK, nil
}
