package model

import "github.com/golang-jwt/jwt/v5"

type Credential struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type Claims struct {
	Username  string `json:"username"`
	TokenType string `json:"token_type"` // "access" or "refresh"
	jwt.RegisteredClaims
}

type RefreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type RegisterRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
	Role     *uint  `json:"role"`     // 0=student, 1=teacher; required
	GroupID  uint   `json:"group_id"` // optional; 0 = no group
}

type User struct {
	Username      string `json:"username"`
	Role          uint   `json:"role"`
	GroupID       uint   `json:"group_id"`        // 0 = not in any group
	ProfilePicURL string `json:"profile_pic_url"` // image link; empty = no picture
}

type SetUserPicRequest struct {
	Username      string `json:"username"`        // optional; empty = caller's own
	ProfilePicURL string `json:"profile_pic_url"`
}

type UsersResponse struct {
	Users []User `json:"users"`
}

// Role levels (see README).
const (
	RoleStudent uint = 0
	RoleTeacher uint = 1
	RoleAdmin   uint = 2
)
