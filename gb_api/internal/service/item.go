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
	inv       repo.InventoryRepo
	users     repo.UserRepo
	buildings repo.BuildingRepo
}

func NewItemSvc(r repo.ItemRepo, inv repo.InventoryRepo, users repo.UserRepo, buildings repo.BuildingRepo) *ItemSvc {
	return &ItemSvc{repo: r, inv: inv, users: users, buildings: buildings}
}

// ownsItem reports whether the user holds itemID loose in their inventory.
func (s *ItemSvc) ownsItem(userID, itemID uint) (bool, error) {
	ids, err := s.inv.QueryInv(userID)
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

// slotAllowsType reports whether user u's building permits an item of itemType in
// slotID (per the building's TypeAllowedSlot). A user with no building, or a
// building that no longer exists, allows nothing.
func (s *ItemSvc) slotAllowsType(u *model.User, slotID, itemType uint) (bool, error) {
	if u.BuildingID == 0 {
		return false, nil
	}
	b, err := s.buildings.GetBuilding(u.BuildingID)
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

func (s *ItemSvc) QueryItems(accessToken string, userID uint) ([]byte, int, error) {
	claims, err := validateAccessToken(accessToken)
	if err != nil {
		return nil, http.StatusUnauthorized, err
	}
	caller, err := s.users.GetUserByID(claims.UserID)
	if err != nil {
		if errors.Is(err, apperr.ErrUserNotFound) {
			return nil, http.StatusUnauthorized, fmt.Errorf("使用者不存在")
		}
		return nil, http.StatusInternalServerError, err
	}
	full := caller.Role >= model.RoleTeacher || caller.ID == userID

	// The queried user must exist; an unknown user_id is a 404.
	if _, err := s.users.GetUserByID(userID); err != nil {
		if errors.Is(err, apperr.ErrUserNotFound) {
			return nil, http.StatusNotFound, fmt.Errorf("使用者不存在")
		}
		return nil, http.StatusInternalServerError, err
	}

	invIDs, err := s.inv.QueryInv(userID)
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

	slotMap, err := s.inv.QuerySlot(userID)
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

	data, err := json.Marshal(model.ItemsResponse{UserID: userID, Inventory: inventory, Slots: slots})
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

// TranInv2Slot moves an owned item from the user's inventory into a slot. The
// item's Type must be allowed in the slot by the user's building. A normal item
// already in the slot is swapped back into the inventory; a broken one blocks the move.
func (s *ItemSvc) TranInv2Slot(accessToken string, userID, itemID, slotID uint) (int, error) {
	caller, status, err := s.blockStudentQuiz2(s.users, accessToken)
	if err != nil {
		return status, err
	}
	if caller.ID != userID {
		return http.StatusForbidden, fmt.Errorf("無法操作其他人的物品")
	}
	has, err := s.ownsItem(caller.ID, itemID)
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
	allowed, err := s.slotAllowsType(caller, slotID, it.Type)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if !allowed {
		return http.StatusBadRequest, fmt.Errorf("slot %d 不允許類型 %d 的物品", slotID, it.Type)
	}
	slot, err := s.inv.QuerySlot(caller.ID)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	held := slot[slotID]
	if held < 0 {
		return http.StatusBadRequest, fmt.Errorf("slot %d (item %d) 已損毀，無法放置物品", slotID, -held)
	}
	if held > 0 {
		if err := s.inv.AddInvItem(caller.ID, uint(held)); err != nil {
			return http.StatusInternalServerError, err
		}
	}
	if err := s.inv.RemoveInvItem(caller.ID, itemID); err != nil {
		return http.StatusInternalServerError, err
	}
	if err := s.inv.SetSlot(caller.ID, slotID, int(itemID)); err != nil {
		return http.StatusInternalServerError, err
	}
	return http.StatusOK, nil
}

// TranSlot2Inv returns the item held in a slot to the user's inventory.
func (s *ItemSvc) TranSlot2Inv(accessToken string, userID, slotID uint) (int, error) {
	caller, status, err := s.blockStudentQuiz2(s.users, accessToken)
	if err != nil {
		return status, err
	}
	if caller.ID != userID {
		return http.StatusForbidden, fmt.Errorf("無法操作其他人的物品")
	}
	slot, err := s.inv.QuerySlot(caller.ID)
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
	if err := s.inv.AddInvItem(caller.ID, uint(itemID)); err != nil {
		return http.StatusInternalServerError, err
	}
	if err := s.inv.SetSlot(caller.ID, slotID, 0); err != nil {
		return http.StatusInternalServerError, err
	}
	return http.StatusOK, nil
}
