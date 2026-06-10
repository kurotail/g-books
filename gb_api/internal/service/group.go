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
	if status, err := requireTeacher(s.users, accessToken); err != nil {
		return status, err
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

func (s *GroupSvc) authorizeGroupEdit(accessToken string, groupID uint) (int, error) {
	claims, err := validateAccessToken(accessToken)
	if err != nil {
		return http.StatusUnauthorized, err
	}
	caller, err := s.users.GetUser(claims.Username)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if caller.GroupID != groupID && caller.Role < model.RoleTeacher {
		return http.StatusForbidden, fmt.Errorf("權限不足")
	}
	return http.StatusOK, nil
}

// SetName renames a group. The caller must be a member of the group, or a
// teacher/admin (who may rename any group).
func (s *GroupSvc) SetName(accessToken string, groupID uint, name string) (int, error) {
	if status, err := s.authorizeGroupEdit(accessToken, groupID); err != nil {
		return status, err
	}
	if err := s.repo.SetGroupName(groupID, name); err != nil {
		return http.StatusInternalServerError, err
	}
	return http.StatusOK, nil
}

// SetBuilding assigns a group's building. The caller must be a member of the
// group, or a teacher/admin. A buildingID of 0 clears the assignment.
func (s *GroupSvc) SetBuilding(accessToken string, groupID uint, buildingID uint) (int, error) {
	if status, err := s.authorizeGroupEdit(accessToken, groupID); err != nil {
		return status, err
	}
	if err := s.repo.SetBuildingID(groupID, buildingID); err != nil {
		return http.StatusInternalServerError, err
	}
	return http.StatusOK, nil
}

// QueryGroup reports the calling user's group, including its members list.
func (s *GroupSvc) QueryGroup(accessToken string) ([]byte, int, error) {
	claims, err := validateAccessToken(accessToken)
	if err != nil {
		return nil, http.StatusUnauthorized, err
	}
	u, err := s.users.GetUser(claims.Username)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if u.GroupID == 0 {
		return nil, http.StatusNotFound, fmt.Errorf("尚未加入任何群組")
	}
	g, err := s.repo.GetGroup(u.GroupID)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(g)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}
