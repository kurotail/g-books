package repo

import (
	"slices"

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
	SetUserProfilePic(username, url string) error
	SetUserBuilding(username string, buildingID uint) error
	SetUserStudents(username string, studentIDs []uint) error
	DeleteUser(username string) (bool, error)
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

// toModelUser maps a users-table row to the model exposed to the service layer.
func toModelUser(u *User) model.User {
	students := make([]uint, 0, len(u.Students))
	for id := range u.Students {
		students = append(students, id)
	}
	slices.Sort(students)
	return model.User{Username: u.Username, Role: u.Role, BuildingID: u.BuildingID, ProfilePicURL: u.ProfilePicURL, Students: students}
}

func (_ *userRepo) SetUserProfilePic(username, url string) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	u := db.users[username]
	if u == nil {
		return apperr.ErrUserNotFound
	}
	u.ProfilePicURL = url
	return nil
}

func (_ *userRepo) SetUserBuilding(username string, buildingID uint) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	u := db.users[username]
	if u == nil {
		return apperr.ErrUserNotFound
	}
	u.BuildingID = buildingID
	return nil
}

// SetUserStudents replaces the user's assigned-student set with the given ids.
func (_ *userRepo) SetUserStudents(username string, studentIDs []uint) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	u := db.users[username]
	if u == nil {
		return apperr.ErrUserNotFound
	}
	students := make(map[uint]struct{}, len(studentIDs))
	for _, id := range studentIDs {
		students[id] = struct{}{}
	}
	u.Students = students
	return nil
}

func (_ *userRepo) CreateUser(username, password string, role uint) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	if db.users[username] != nil {
		return apperr.ErrUserExists
	}
	db.users[username] = &User{
		Username:  username,
		Password:  password,
		Role:      role,
		Inventory: make(map[uint]struct{}),
		Slots:     make(map[uint]int),
		Students:  make(map[uint]struct{}),
	}
	return nil
}

// DeleteUser removes a user. The bool reports whether the user existed.
func (_ *userRepo) DeleteUser(username string) (bool, error) {
	db.mu.Lock()
	defer db.mu.Unlock()
	if db.users[username] == nil {
		return false, nil
	}
	delete(db.users, username)
	return true, nil
}

func InitUserRepo() UserRepo {
	return &userRepo{}
}
