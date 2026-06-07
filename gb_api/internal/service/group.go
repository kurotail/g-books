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

type GroupSvc struct {
	repo  repo.GroupRepo
	users repo.UserRepo
}

func NewGroupSvc(r repo.GroupRepo, users repo.UserRepo) *GroupSvc {
	return &GroupSvc{repo: r, users: users}
}

func (s *GroupSvc) SetGroup(accessToken, username string, groupID uint) (int, error) {
	claims, err := validateAccessToken(accessToken)
	if err != nil {
		return http.StatusUnauthorized, err
	}
	caller, err := s.users.GetUser(claims.Username)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if caller.Role < model.RoleTeacher {
		return http.StatusForbidden, fmt.Errorf("權限不足")
	}
	if _, err := s.users.GetUser(username); err != nil {
		if errors.Is(err, apperr.ErrUserNotFound) {
			return http.StatusNotFound, fmt.Errorf("使用者不存在: %q", username)
		}
		return http.StatusInternalServerError, err
	}
	if err := s.repo.SetUserGroup(username, groupID); err != nil {
		return http.StatusInternalServerError, err
	}
	return http.StatusOK, nil
}

// QueryGroup reports which group the calling user belongs to.
func (s *GroupSvc) QueryGroup(accessToken string) ([]byte, int, error) {
	claims, err := validateAccessToken(accessToken)
	if err != nil {
		return nil, http.StatusUnauthorized, err
	}
	u, err := s.users.GetUser(claims.Username)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if u.GroupID == nil {
		return nil, http.StatusNotFound, fmt.Errorf("尚未加入任何群組")
	}
	data, err := json.Marshal(model.GroupResponse{GroupID: *u.GroupID})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

// QueryMember lists the members of a group. Any authenticated user may call it.
func (s *GroupSvc) QueryMember(accessToken string, groupID uint) ([]byte, int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return nil, http.StatusUnauthorized, err
	}
	members, err := s.repo.GetGroupMembers(groupID)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(model.MembersResponse{GroupID: groupID, Members: members})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}
