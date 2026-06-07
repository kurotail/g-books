package repo

import (
	apperr "gb-api/internal/error"
	"gb-api/internal/model"
)

// UserRepo is the user-account table: credentials, roles, and membership. It is
// shared by services that need to identify or authorize users.
type UserRepo interface {
	ValidateCredentials(username, password string) (bool, error)
	GetAllUsers() ([]model.User, error)
	GetUser(username string) (model.User, error)
	CreateUser(username, password string, role uint) error
}

type userRepo struct{}

func (_ *userRepo) ValidateCredentials(username, password string) (bool, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	u := db.users[username]
	return u != nil && u.Password == password, nil
}

func (_ *userRepo) GetAllUsers() ([]model.User, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	users := make([]model.User, 0, len(db.users))
	for _, u := range db.users {
		users = append(users, toModelUser(u))
	}
	return users, nil
}

func (_ *userRepo) GetUser(username string) (model.User, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	u := db.users[username]
	if u == nil {
		return model.User{}, apperr.ErrUserNotFound
	}
	return toModelUser(u), nil
}

// toModelUser maps a users-table row to the model exposed to the service layer,
// copying GroupID so callers can't mutate the stored row.
func toModelUser(u *User) model.User {
	gid := u.GroupID
	if gid != nil {
		v := *gid
		gid = &v
	}
	return model.User{Username: u.Username, Role: u.Role, GroupID: gid}
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
