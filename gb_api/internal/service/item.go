package service

import (
	"encoding/json"
	"fmt"
	"net/http"

	"gb-api/internal/repo"
)

type ItemSvc struct {
	repo repo.ItemRepo
}

func NewItemSvc(r repo.ItemRepo) *ItemSvc {
	return &ItemSvc{repo: r}
}

func (s *ItemSvc) QueryInv(accessToken string, groupID uint) ([]byte, int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return nil, http.StatusUnauthorized, err
	}
	inv, err := s.repo.QueryInv(groupID)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(inv)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func (s *ItemSvc) QuerySlot(accessToken string, groupID uint) ([]byte, int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return nil, http.StatusUnauthorized, err
	}
	slot, err := s.repo.QuerySlot(groupID)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(slot)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func (s *ItemSvc) DeleteSlotItem(accessToken string, groupID, slotID uint) (int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return http.StatusUnauthorized, err
	}
	if err := s.repo.SetSlot(groupID, slotID, 0); err != nil {
		return http.StatusInternalServerError, err
	}
	return http.StatusOK, nil
}

func (s *ItemSvc) IncreaseInvItem(accessToken string, groupID, itemID, itemCount uint) (int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return http.StatusUnauthorized, err
	}
	inv, err := s.repo.QueryInv(groupID)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if err := s.repo.SetInv(groupID, itemID, inv[itemID]+itemCount); err != nil {
		return http.StatusInternalServerError, err
	}
	return http.StatusOK, nil
}

func (s *ItemSvc) TranInv2Slot(accessToken string, groupID, itemID, slotID uint) (int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return http.StatusUnauthorized, err
	}
	inv, err := s.repo.QueryInv(groupID)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	count := inv[itemID]
	if count == 0 {
		return http.StatusBadRequest, fmt.Errorf("item %d 庫存不足", itemID)
	}
	if err := s.repo.SetInv(groupID, itemID, count-1); err != nil {
		return http.StatusInternalServerError, err
	}
	if err := s.repo.SetSlot(groupID, slotID, itemID); err != nil {
		return http.StatusInternalServerError, err
	}
	return http.StatusOK, nil
}

func (s *ItemSvc) TranSlot2Inv(accessToken string, groupID, slotID uint) (int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return http.StatusUnauthorized, err
	}
	slot, err := s.repo.QuerySlot(groupID)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	itemID, ok := slot[slotID]
	if !ok {
		return http.StatusBadRequest, fmt.Errorf("slot %d 不存在", slotID)
	}
	inv, err := s.repo.QueryInv(groupID)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if err := s.repo.SetInv(groupID, itemID, inv[itemID]+1); err != nil {
		return http.StatusInternalServerError, err
	}
	if err := s.repo.SetSlot(groupID, slotID, 0); err != nil {
		return http.StatusInternalServerError, err
	}
	return http.StatusOK, nil
}
