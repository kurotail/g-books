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
	data, err := json.Marshal(model.InventoryResponse{GroupID: groupID, Inventory: inv})
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
	data, err := json.Marshal(model.SlotsResponse{GroupID: groupID, Slots: slot})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func (s *ItemSvc) TranInv2Slot(accessToken string, groupID, itemID, slotID uint) (int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return http.StatusUnauthorized, err
	}
	if err := s.repo.ChangeInv(groupID, itemID, -1); err != nil {
		if errors.Is(err, apperr.ErrInsufficientStock) {
			return http.StatusBadRequest, fmt.Errorf("item %d %w", itemID, err)
		}
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
	if itemID<0 {
		return http.StatusBadRequest, fmt.Errorf("slot %d (item %d) 已損毀", slotID, itemID)
	}
	if err := s.repo.ChangeInv(groupID, uint(itemID), 1); err != nil {
		return http.StatusInternalServerError, err
	}
	if err := s.repo.SetSlot(groupID, slotID, 0); err != nil {
		return http.StatusInternalServerError, err
	}
	return http.StatusOK, nil
}
