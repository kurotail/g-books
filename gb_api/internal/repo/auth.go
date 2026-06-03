package repo

import (
	"sync"
)

// memAuthRepo is an in-memory implementation backed by Go collections.
type memAuthRepo struct {
	users         map[string]string // username → password
	refreshTokens sync.Map
}

var mem_repo = memAuthRepo{
	users: map[string]string{
		"user": "password123",
	},
}

type AuthRepo interface {
	ValidateCredentials(username, password string) bool
	StoreRefreshToken(token string)
	ConsumeRefreshToken(token string) bool
}

type authRepo struct {}

func (_ *authRepo) ValidateCredentials(username, password string) bool {
	stored, ok := mem_repo.users[username]
	return ok && stored == password
}

func (_ *authRepo) StoreRefreshToken(token string) {
	mem_repo.refreshTokens.Store(token, struct{}{})
}

func (_ *authRepo) ConsumeRefreshToken(token string) bool {
	_, ok := mem_repo.refreshTokens.LoadAndDelete(token)
	return ok
}

func InitAuthRepo() *authRepo {
	return &authRepo{}
}
