package model

type SetGroupRequest struct {
	Username string `json:"username"`
	GroupID  *uint  `json:"group_id"`
}

type QueryMemberRequest struct {
	GroupID *uint `json:"group_id"`
}

type GroupResponse struct {
	GroupID uint `json:"group_id"`
}

type MembersResponse struct {
	GroupID uint     `json:"group_id"`
	Members []string `json:"members"`
}
