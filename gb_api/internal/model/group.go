package model

type SetGroupRequest struct {
	Username string `json:"username"`
	GroupID  *uint  `json:"group_id"`
}

type QueryMemberRequest struct {
	GroupID *uint `json:"group_id"`
}

type SetGroupNameRequest struct {
	GroupID *uint  `json:"group_id"`
	Name    string `json:"name"`
}

type SetBuildingRequest struct {
	GroupID    *uint `json:"group_id"`
	BuildingID *uint `json:"building_id"` // 0 = no building
}

// Group is the aggregate view of a group: its name, building, and members.
type Group struct {
	ID         uint
	Name       string
	BuildingID uint
	Members    []string
}

type GroupResponse struct {
	GroupID    uint   `json:"group_id"`
	Name       string `json:"name"`
	BuildingID uint   `json:"building_id"`
}

type MembersResponse struct {
	GroupID uint     `json:"group_id"`
	Name    string   `json:"name"`
	Members []string `json:"members"`
}
