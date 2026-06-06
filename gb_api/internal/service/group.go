package service

import (
	"encoding/json"
	"fmt"
	"net/http"

	"gb-api/internal/model"
	"gb-api/internal/repo"
)

type GroupSvc struct {
	repo repo.GroupRepo
}

func NewGroupSvc(r repo.GroupRepo) *GroupSvc {
	return &GroupSvc{repo: r}
}

func (s *GroupSvc) SetGroup(accessToken, username string, groupID uint) (int, error) {
	claims, err := validateAccessToken(accessToken)
	if err != nil {
		return http.StatusUnauthorized, err
	}
	role, err := s.repo.GetRole(claims.Username)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if role <= model.RoleStudent {
		return http.StatusForbidden, fmt.Errorf("權限不足")
	}
	ok, err := s.repo.UserExists(username)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if !ok {
		return http.StatusNotFound, fmt.Errorf("使用者不存在: %q", username)
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
	groupID, ok, err := s.repo.GetUserGroup(claims.Username)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if !ok {
		return nil, http.StatusNotFound, fmt.Errorf("尚未加入任何群組")
	}
	data, err := json.Marshal(model.GroupResponse{GroupID: groupID})
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
