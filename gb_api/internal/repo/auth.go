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
	ValidateCredentials(username, password string) (bool, error)
	StoreRefreshToken(token string) error
	ConsumeRefreshToken(token string) (bool, error)
}

type authRepo struct {}

func (_ *authRepo) ValidateCredentials(username, password string) (bool, error) {
	stored, ok := mem_repo.users[username]
	return ok && stored == password, nil
}

func (_ *authRepo) StoreRefreshToken(token string) error {
	mem_repo.refreshTokens.Store(token, struct{}{})
	return nil
}

func (_ *authRepo) ConsumeRefreshToken(token string) (bool, error) {
	_, ok := mem_repo.refreshTokens.LoadAndDelete(token)
	return ok, nil
}

func InitAuthRepo() *authRepo {
	return &authRepo{}
}
