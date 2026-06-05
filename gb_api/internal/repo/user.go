package repo

import (
	apperr "gb-api/internal/error"
)

// UserRepo is the user-account table: credentials, roles, and membership. It is
// shared by services that need to identify or authorize users.
type UserRepo interface {
	ValidateCredentials(username, password string) (bool, error)
	GetAllUsers() ([]string, error)
	GetRole(username string) (uint, error)
	CreateUser(username, password string, role uint) error
}

type userRepo struct{}

func (_ *userRepo) ValidateCredentials(username, password string) (bool, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	u := db.users[username]
	return u != nil && u.Password == password, nil
}

func (_ *userRepo) GetAllUsers() ([]string, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	users := make([]string, 0, len(db.users))
	for username := range db.users {
		users = append(users, username)
	}
	return users, nil
}

func (_ *userRepo) GetRole(username string) (uint, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	return roleOf(username), nil
}

func (_ *userRepo) CreateUser(username, password string, role uint) error {
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

func InitUserRepo() UserRepo {
	return &userRepo{}
}
