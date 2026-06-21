package model

// Pointers distinguish a missing field from a valid zero value (slot 0 exists).
type QueryItemRequest struct {
	UserID *uint `json:"user_id"`
}

type TranInv2SlotRequest struct {
	UserID *uint `json:"user_id"`
	ItemID *uint `json:"item_id"`
	SlotID *uint `json:"slot_id"`
}

type TranSlot2InvRequest struct {
	UserID *uint `json:"user_id"`
	SlotID *uint `json:"slot_id"`
}

// Item is a row in the items table: a unique item instance with a Type (which the
// building constrains and grades) and an optional linked QuestionID (0 = none).
type Item struct {
	ItemID     uint
	Type       uint
	QuestionID uint
}

// SlotItem is a slotted item hydrated from user_slots joined to items: the item
// itself plus whether the slot holds it broken.
type SlotItem struct {
	Item
	Broken bool
}

// ItemView is one owned item as returned by the query endpoint. For the restricted
// (type-only) student view, ItemID and QuestionID are zero and omitted.
type ItemView struct {
	ItemID     uint `json:"item_id,omitempty"`
	Type       uint `json:"type"`
	QuestionID uint `json:"question_id,omitempty"`
}

// SlotView is a slotted item, like ItemView plus whether the item is broken and the
// set of attacker user ids currently barred from attacking this slot (failed attackers,
// cleared on repair); omitted when empty.
type SlotView struct {
	ItemID           uint   `json:"item_id,omitempty"`
	Type             uint   `json:"type"`
	QuestionID       uint   `json:"question_id,omitempty"`
	Broken           bool   `json:"broken"`
	BlockedAttackers []uint `json:"blocked_attackers,omitempty"`
}

type ItemsResponse struct {
	UserID    uint              `json:"user_id"`
	Inventory []ItemView        `json:"inventory"`
	Slots     map[uint]SlotView `json:"slots"`
}
