package model

// Pointers distinguish a missing field from a valid zero value (group 0 and
// slot 0 both exist).
type QueryItemRequest struct {
	GroupID *uint `json:"group_id"`
}

type TranInv2SlotRequest struct {
	GroupID *uint `json:"group_id"`
	ItemID  *uint `json:"item_id"`
	SlotID  *uint `json:"slot_id"`
}

type TranSlot2InvRequest struct {
	GroupID *uint `json:"group_id"`
	SlotID  *uint `json:"slot_id"`
}

type ItemsResponse struct {
	GroupID   uint          `json:"group_id"`
	Inventory map[uint]uint `json:"inventory"`
	Slots     map[uint]int  `json:"slots"`
}
