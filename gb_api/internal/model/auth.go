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

// Permission levels (see README).
const (
	PermStudent uint = 0
	PermTeacher uint = 1
	PermAdmin   uint = 2
)
