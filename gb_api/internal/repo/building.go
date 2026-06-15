package repo

import (
	"fmt"

	apperr "gb-api/internal/error"
	"gb-api/internal/model"
)

type BuildingRepo interface {
	CreateBuilding(name, layout string, typeAllowedSlot map[uint][]uint, difficultyType map[uint][]uint) (uint, error)
	UpdateBuilding(id uint, name, layout string, typeAllowedSlot map[uint][]uint, difficultyType map[uint][]uint) error
	GetBuilding(id uint) (model.Building, error)
	GetAllBuildings() ([]model.Building, error)
}

type buildingRepo struct{}

func toModelBuilding(b *Building) model.Building {
	name := b.Name
	if name == "" {
		name = fmt.Sprintf("Building %d", b.ID)
	}
	return model.Building{
		ID:              b.ID,
		Name:            name,
		Layout:          b.Layout,
		TypeAllowedSlot: copyUintSliceMap(b.TypeAllowedSlot),
		DifficultyType:  copyUintSliceMap(b.DifficultyType),
	}
}

// copyUintSliceMap deep-copies a map[uint][]uint (and its slices) so the stored
// building can't be mutated through a returned model.
func copyUintSliceMap(src map[uint][]uint) map[uint][]uint {
	dst := make(map[uint][]uint, len(src))
	for k, vals := range src {
		cp := make([]uint, len(vals))
		copy(cp, vals)
		dst[k] = cp
	}
	return dst
}

func (_ *buildingRepo) CreateBuilding(name, layout string, typeAllowedSlot map[uint][]uint, difficultyType map[uint][]uint) (uint, error) {
	db.mu.Lock()
	defer db.mu.Unlock()
	id := db.nextBuildingID
	db.nextBuildingID++
	db.buildings[id] = &Building{
		ID:              id,
		Name:            name,
		Layout:          layout,
		TypeAllowedSlot: copyUintSliceMap(typeAllowedSlot),
		DifficultyType:  copyUintSliceMap(difficultyType),
	}
	return id, nil
}

func (_ *buildingRepo) UpdateBuilding(id uint, name, layout string, typeAllowedSlot map[uint][]uint, difficultyType map[uint][]uint) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	b := db.buildings[id]
	if b == nil {
		return apperr.ErrBuildingNotFound
	}
	b.Name = name
	b.Layout = layout
	b.TypeAllowedSlot = copyUintSliceMap(typeAllowedSlot)
	b.DifficultyType = copyUintSliceMap(difficultyType)
	return nil
}

func (_ *buildingRepo) GetBuilding(id uint) (model.Building, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	b := db.buildings[id]
	if b == nil {
		return model.Building{}, apperr.ErrBuildingNotFound
	}
	return toModelBuilding(b), nil
}

func (_ *buildingRepo) GetAllBuildings() ([]model.Building, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	buildings := make([]model.Building, 0, len(db.buildings))
	for _, b := range db.buildings {
		buildings = append(buildings, toModelBuilding(b))
	}
	return buildings, nil
}

func InitBuildingRepo() BuildingRepo {
	return &buildingRepo{}
}
