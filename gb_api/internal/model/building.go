package model

type CreateBuildingRequest struct {
	Name            string          `json:"name"`
	Layout          string          `json:"layout"`            // frontend-specific JSON blob
	TypeAllowedSlot map[uint][]uint `json:"item_allowed_slot"` // type -> allowed slot_ids
	DifficultyType  map[uint][]uint `json:"difficulty_type"`   // difficulty -> types
}

type Building struct {
	ID              uint            `json:"building_id"`
	Name            string          `json:"name"`
	Layout          string          `json:"layout"`
	TypeAllowedSlot map[uint][]uint `json:"item_allowed_slot"`
	DifficultyType  map[uint][]uint `json:"difficulty_type"`
}
