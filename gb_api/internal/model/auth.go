package model

import "github.com/golang-jwt/jwt/v5"

type Credential struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type Claims struct {
	UserID    uint   `json:"user_id"`    // immutable user id; survives username changes
	TokenType string `json:"token_type"` // "access" or "refresh"
	jwt.RegisteredClaims
}

type RefreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type RegisterRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
	Role     *uint  `json:"role"` // 0=student, 1=teacher; required
}

type User struct {
	ID            uint   `json:"id"` // numeric primary key; read-only (server-assigned, never accepted as input)
	Username      string `json:"username"`
	Role          uint   `json:"role"`
	BuildingID    uint   `json:"building_id"`     // 0 = no building assigned
	ProfilePicURL string `json:"profile_pic_url"` // image link; empty = no picture
	Students      []uint `json:"students"`        // assigned student_ids, sorted ascending
}

type SetUserPicRequest struct {
	Username      string `json:"username"` // optional; empty = caller's own
	ProfilePicURL string `json:"profile_pic_url"`
}

// SetUserBuildingRequest is the body of POST /api/users/building; the caller sets
// their own building. A BuildingID of 0 clears the assignment.
type SetUserBuildingRequest struct {
	BuildingID *uint `json:"building_id"`
}

type SetUsernameRequest struct {
	Username string `json:"username"`
}

type SetPasswordRequest struct {
	OldPassword string `json:"old_password"`
	NewPassword string `json:"new_password"`
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
