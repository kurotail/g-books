package service

import (
	"encoding/json"
	"errors"
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
func (s *BuildingSvc) Create(accessToken, name, layout string, typeAllowedSlot map[uint][]uint, difficultyType map[uint][]uint) ([]byte, int, error) {
	if status, err := requireTeacher(s.users, accessToken); err != nil {
		return nil, status, err
	}
	id, err := s.repo.CreateBuilding(name, layout, typeAllowedSlot, difficultyType)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	b, err := s.repo.GetBuilding(id)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(
		model.Building{
			ID:              b.ID,
			Name:            b.Name,
			Layout:          b.Layout,
			TypeAllowedSlot: b.TypeAllowedSlot,
			DifficultyType:  b.DifficultyType,
		},
	)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

// Update replaces every field of the building identified by id. Only teachers/admins may update.
func (s *BuildingSvc) Update(accessToken string, id uint, name, layout string, typeAllowedSlot map[uint][]uint, difficultyType map[uint][]uint) ([]byte, int, error) {
	if status, err := requireTeacher(s.users, accessToken); err != nil {
		return nil, status, err
	}
	if err := s.repo.UpdateBuilding(id, name, layout, typeAllowedSlot, difficultyType); err != nil {
		if errors.Is(err, apperr.ErrBuildingNotFound) {
			return nil, http.StatusNotFound, err
		}
		return nil, http.StatusInternalServerError, err
	}
	b, err := s.repo.GetBuilding(id)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(
		model.Building{
			ID:              b.ID,
			Name:            b.Name,
			Layout:          b.Layout,
			TypeAllowedSlot: b.TypeAllowedSlot,
			DifficultyType:  b.DifficultyType,
		},
	)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

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
	data, err := json.Marshal(
		model.Building{
			ID:              b.ID,
			Name:            b.Name,
			Layout:          b.Layout,
			TypeAllowedSlot: b.TypeAllowedSlot,
			DifficultyType:  b.DifficultyType,
		},
	)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func (s *BuildingSvc) List(accessToken string) ([]byte, int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return nil, http.StatusUnauthorized, err
	}
	buildings, err := s.repo.GetAllBuildings()
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	resp := make([]model.Building, 0, len(buildings))
	for _, b := range buildings {
		resp = append(resp,
			model.Building{
				ID:              b.ID,
				Name:            b.Name,
				Layout:          b.Layout,
				TypeAllowedSlot: b.TypeAllowedSlot,
				DifficultyType:  b.DifficultyType,
			},
		)
	}
	data, err := json.Marshal(resp)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}
