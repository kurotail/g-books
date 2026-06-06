package model

type ItemOperation struct {
	AccessToken string `json:"access_token"`
	GroupID     uint   `json:"group_id"`
	ItemID      *uint  `json:"item_id"`
	SlotID      *uint  `json:"slot_id"`
}
