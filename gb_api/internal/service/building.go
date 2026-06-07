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

type BuildingSvc struct {
	repo  repo.BuildingRepo
	users repo.UserRepo
}

func NewBuildingSvc(r repo.BuildingRepo, users repo.UserRepo) *BuildingSvc {
	return &BuildingSvc{repo: r, users: users}
}

// Create defines a new building. Only teachers/admins may create buildings.
func (s *BuildingSvc) Create(accessToken, name, layout string, itemAllowedSlot map[uint][]uint) ([]byte, int, error) {
	claims, err := validateAccessToken(accessToken)
	if err != nil {
		return nil, http.StatusUnauthorized, err
	}
	caller, err := s.users.GetUser(claims.Username)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if caller.Role < model.RoleTeacher {
		return nil, http.StatusForbidden, fmt.Errorf("權限不足")
	}
	id, err := s.repo.CreateBuilding(name, layout, itemAllowedSlot)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	b, err := s.repo.GetBuilding(id)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(toBuildingResponse(b))
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

// Get returns a single building by id. Any authenticated user may call it.
func (s *BuildingSvc) Get(accessToken string, id uint) ([]byte, int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return nil, http.StatusUnauthorized, err
	}
	b, err := s.repo.GetBuilding(id)
	if err != nil {
		if errors.Is(err, apperr.ErrBuildingNotFound) {
			return nil, http.StatusNotFound, err
		}
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(toBuildingResponse(b))
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

// List returns every building. Any authenticated user may call it.
func (s *BuildingSvc) List(accessToken string) ([]byte, int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return nil, http.StatusUnauthorized, err
	}
	buildings, err := s.repo.GetAllBuildings()
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	resp := make([]model.BuildingResponse, 0, len(buildings))
	for _, b := range buildings {
		resp = append(resp, toBuildingResponse(b))
	}
	data, err := json.Marshal(resp)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func toBuildingResponse(b model.Building) model.BuildingResponse {
	return model.BuildingResponse{
		BuildingID:      b.ID,
		Name:            b.Name,
		Layout:          b.Layout,
		ItemAllowedSlot: b.ItemAllowedSlot,
	}
}
