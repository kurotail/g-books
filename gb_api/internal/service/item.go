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

// slotAllowsType reports whether user u's building permits an item of itemType.
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

	// One join query each — no per-item GetItem lookups.
	invItems, err := s.inv.QueryInventory(userID)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	inventory := make([]model.ItemView, 0, len(invItems))
	for _, it := range invItems {
		inventory = append(inventory, itemView(it, full))
	}

	slotItems, err := s.inv.QuerySlotItems(userID)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	slots := make(map[uint]model.SlotView, len(slotItems))
	for slotID, si := range slotItems {
		slots[slotID] = slotView(si.Item, si.Broken, full)
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

func (s *ItemSvc) TranInv2Slot(accessToken string, userID, itemID, slotID uint) (int, error) {
	caller, status, err := s.blockStudentQuiz2(s.users, accessToken)
	if err != nil {
		return status, err
	}
	if caller.ID != userID {
		return http.StatusForbidden, fmt.Errorf("無法操作其他人的物品")
	}
	it, owned, err := s.inv.OwnedItem(caller.ID, itemID)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if !owned {
		return http.StatusBadRequest, fmt.Errorf("item %d 不在庫存中", itemID)
	}
	// Type must be allowed
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
		// broken one blocks the move
		return http.StatusBadRequest, fmt.Errorf("slot %d (item %d) 已損毀，無法放置物品", slotID, -held)
	}
	if held > 0 {
		// swapped back into the inventory
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
