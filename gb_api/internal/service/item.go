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
	repo  repo.ItemRepo
	users repo.UserRepo
}

func NewItemSvc(r repo.ItemRepo, users repo.UserRepo) *ItemSvc {
	return &ItemSvc{repo: r, users: users}
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

// QueryItems returns all of a group's items — its inventory and its slots — in a
// single response. Any authenticated user may call it.
func (s *ItemSvc) QueryItems(accessToken string, groupID uint) ([]byte, int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return nil, http.StatusUnauthorized, err
	}
	inv, err := s.repo.QueryInv(groupID)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	slot, err := s.repo.QuerySlot(groupID)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(model.ItemsResponse{GroupID: groupID, Inventory: inv, Slots: slot})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func (s *ItemSvc) TranInv2Slot(accessToken string, groupID, itemID, slotID uint) (int, error) {
	if status, err := s.blockStudentDuringQuiz(accessToken); err != nil {
		return status, err
	}
	slot, err := s.repo.QuerySlot(groupID)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	held := slot[slotID]
	if held < 0 {
		return http.StatusBadRequest, fmt.Errorf("slot %d (item %d) 已損毀，無法放置物品", slotID, -held)
	}
	if err := s.repo.ChangeInv(groupID, itemID, -1); err != nil {
		if errors.Is(err, apperr.ErrInsufficientStock) {
			return http.StatusBadRequest, fmt.Errorf("item %d %w", itemID, err)
		}
		return http.StatusInternalServerError, err
	}
	if held > 0 {
		if err := s.repo.ChangeInv(groupID, uint(held), 1); err != nil {
			return http.StatusInternalServerError, err
		}
	}
	if err := s.repo.SetSlot(groupID, slotID, itemID); err != nil {
		return http.StatusInternalServerError, err
	}
	return http.StatusOK, nil
}

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
	if err := s.repo.ChangeInv(groupID, uint(itemID), 1); err != nil {
		return http.StatusInternalServerError, err
	}
	if err := s.repo.SetSlot(groupID, slotID, 0); err != nil {
		return http.StatusInternalServerError, err
	}
	return http.StatusOK, nil
}
