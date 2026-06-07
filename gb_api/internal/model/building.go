package model

type CreateBuildingRequest struct {
	Name            string          `json:"name"`
	Layout          string          `json:"layout"`            // frontend-specific JSON blob
	TypeAllowedSlot map[uint][]uint `json:"item_allowed_slot"` // item_id -> allowed slot_ids
	TypeDifficulty  map[uint]uint   `json:"item_difficulty"`   // item_id -> difficulty
}

type Building struct {
	ID              uint
	Name            string
	Layout          string
	TypeAllowedSlot map[uint][]uint
	TypeDifficulty  map[uint]uint
}

type BuildingResponse struct {
	BuildingID      uint            `json:"building_id"`
	Name            string          `json:"name"`
	Layout          string          `json:"layout"`
	TypeAllowedSlot map[uint][]uint `json:"item_allowed_slot"`
	TypeDifficulty  map[uint]uint   `json:"item_difficulty"`
}
