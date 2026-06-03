package model

import (
	"github.com/golang-jwt/jwt/v5"
)

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

type ItemOperation struct {
	AccessToken string `json:"access_token"`
	GroupID      uint  `json:"group_id"`
	ItemID      *uint  `json:"item_id"`
	ItemCount   *uint  `json:"item_count"`
	SlotID      *uint  `json:"slot_id"`
}
