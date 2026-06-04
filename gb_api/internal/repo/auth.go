package repo

import (
	apperr "gb-api/internal/error"
)

type AuthRepo interface {
	ValidateCredentials(username, password string) (bool, error)
	StoreRefreshToken(token string) error
	ConsumeRefreshToken(token string) (bool, error)
	GetAllUsers() ([]string, error)
	GetRole(username string) (uint, error)
	CreateUser(username, password string, role uint) error
}

type authRepo struct{}

func (_ *authRepo) ValidateCredentials(username, password string) (bool, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	u := db.users[username]
	return u != nil && u.Password == password, nil
}

func (_ *authRepo) StoreRefreshToken(token string) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	db.refreshTokens[token] = struct{}{}
	return nil
}

func (_ *authRepo) ConsumeRefreshToken(token string) (bool, error) {
	db.mu.Lock()
	defer db.mu.Unlock()
	if _, ok := db.refreshTokens[token]; ok {
		delete(db.refreshTokens, token)
		return true, nil
	}
	return false, nil
}

func (_ *authRepo) GetAllUsers() ([]string, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	users := make([]string, 0, len(db.users))
	for username := range db.users {
		users = append(users, username)
	}
	return users, nil
}

func (_ *authRepo) GetRole(username string) (uint, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	return roleOf(username), nil
}

func (_ *authRepo) CreateUser(username, password string, role uint) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	if db.users[username] != nil {
		return apperr.ErrUserExists
	}
	db.users[username] = &User{
		Username: username,
		Password: password,
		Role:     role,
		GroupID:  nil,
	}
	return nil
}

func InitAuthRepo() AuthRepo {
	return &authRepo{}
}
