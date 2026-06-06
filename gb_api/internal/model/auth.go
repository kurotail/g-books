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
	Role     *uint  `json:"role"` // 0=student, 1=teacher; required
}

type UsersResponse struct {
	Users []string `json:"users"`
}

// Role levels (see README).
const (
	RoleStudent uint = 0
	RoleTeacher uint = 1
	RoleAdmin   uint = 2
)
