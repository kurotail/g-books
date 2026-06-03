package repo

import (
	"sync"
)

type memAuthRepo struct {
	users         map[string]string // username -> password
	refreshTokens sync.Map
	groupInv      map[uint]uint // itemID -> itemCount
	groupSlot   map[uint]uint // slotID -> itemID
}

var mem_db = memAuthRepo{
	users: map[string]string{
		"user": "password123",
	},
	groupInv: map[uint]uint{
		0: 1,
		1: 1,
		3: 2,
	},
	groupSlot: map[uint]uint{
		0: 1,
		2: 3,
		5: 0,
	},
}

type AuthRepo interface {
	ValidateCredentials(username, password string) (bool, error)
	StoreRefreshToken(token string) error
	ConsumeRefreshToken(token string) (bool, error)
}

type authRepo struct {}

func (_ *authRepo) ValidateCredentials(username, password string) (bool, error) {
	stored, ok := mem_db.users[username]
	return ok && stored == password, nil
}

func (_ *authRepo) StoreRefreshToken(token string) error {
	mem_db.refreshTokens.Store(token, struct{}{})
	return nil
}

func (_ *authRepo) ConsumeRefreshToken(token string) (bool, error) {
	_, ok := mem_db.refreshTokens.LoadAndDelete(token)
	return ok, nil
}

func InitAuthRepo() AuthRepo {
	return &authRepo{}
}
