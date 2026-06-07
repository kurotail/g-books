package repo

import (
	"fmt"

	apperr "gb-api/internal/error"
	"gb-api/internal/model"
)

type BuildingRepo interface {
	CreateBuilding(name, layout string, itemAllowedSlot map[uint][]uint, itemDifficulty map[uint]uint) (uint, error)
	GetBuilding(id uint) (model.Building, error)
	GetAllBuildings() ([]model.Building, error)
}

type buildingRepo struct{}

// defaultBuildingName is used when a building has no name set.
func defaultBuildingName(id uint) string {
	return fmt.Sprintf("Building %d", id)
}

// toModelBuilding maps a stored building row to its public model, deep-copying
// ItemAllowedSlot (and its slices) and ItemDifficulty so callers can't mutate the store.
func toModelBuilding(b *Building) model.Building {
	allowed := make(map[uint][]uint, len(b.TypeAllowedSlot))
	for itemID, slots := range b.TypeAllowedSlot {
		cp := make([]uint, len(slots))
		copy(cp, slots)
		allowed[itemID] = cp
	}
	name := b.Name
	if name == "" {
		name = defaultBuildingName(b.ID)
	}
	return model.Building{
		ID:              b.ID,
		Name:            name,
		Layout:          b.Layout,
		TypeAllowedSlot: allowed,
		TypeDifficulty:  copyItemDifficulty(b.TypeDifficulty),
	}
}

// copyItemDifficulty returns a shallow copy of an item_id -> difficulty map so the
// stored building can't be mutated through a returned model.
func copyItemDifficulty(src map[uint]uint) map[uint]uint {
	dst := make(map[uint]uint, len(src))
	for itemID, difficulty := range src {
		dst[itemID] = difficulty
	}
	return dst
}

func (_ *buildingRepo) CreateBuilding(name, layout string, itemAllowedSlot map[uint][]uint, itemDifficulty map[uint]uint) (uint, error) {
	db.mu.Lock()
	defer db.mu.Unlock()
	id := db.nextBuildingID
	db.nextBuildingID++
	allowed := make(map[uint][]uint, len(itemAllowedSlot))
	for itemID, slots := range itemAllowedSlot {
		cp := make([]uint, len(slots))
		copy(cp, slots)
		allowed[itemID] = cp
	}
	db.buildings[id] = &Building{
		ID:              id,
		Name:            name,
		Layout:          layout,
		TypeAllowedSlot: allowed,
		TypeDifficulty:  copyItemDifficulty(itemDifficulty),
	}
	return id, nil
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
