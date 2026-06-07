package model

type CreateBuildingRequest struct {
	Name            string          `json:"name"`
	Layout          string          `json:"layout"`            // frontend-specific JSON blob
	ItemAllowedSlot map[uint][]uint `json:"item_allowed_slot"` // item_id -> allowed slot_ids
}

// Building is the aggregate view of a building: its name, layout, and the slots
// each item is allowed in.
type Building struct {
	ID              uint
	Name            string
	Layout          string
	ItemAllowedSlot map[uint][]uint
}

type BuildingResponse struct {
	BuildingID      uint            `json:"building_id"`
	Name            string          `json:"name"`
	Layout          string          `json:"layout"`
	ItemAllowedSlot map[uint][]uint `json:"item_allowed_slot"`
}
