package model

type SetGroupRequest struct {
	Username string `json:"username"`
	GroupID  *uint  `json:"group_id"`
}

type SetGroupNameRequest struct {
	GroupID *uint  `json:"group_id"`
	Name    string `json:"name"`
}

type SetBuildingRequest struct {
	GroupID    *uint `json:"group_id"`
	BuildingID *uint `json:"building_id"` // 0 = no building
}

type SetGroupPicRequest struct {
	GroupID       *uint  `json:"group_id"`
	ProfilePicURL string `json:"profile_pic_url"`
}

type Group struct {
	ID            uint     `json:"group_id"`
	Name          string   `json:"name"`
	BuildingID    uint     `json:"building_id"`
	Members       []string `json:"members"`
	ProfilePicURL string   `json:"profile_pic_url"`
}
