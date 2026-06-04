package repo

import (
	apperr "gb-api/internal/error"
	"gb-api/internal/model"
	"sync"
	"time"
)

var questionList = []model.Question{
	{
		Description: "What is six times three?\n(a)6\n(b)18\n(c)9\n(d)12",
		Answer:      1,
	},
	{
		Description: "Who is F\n(a)HRM\n(b)M's child\n(c)White cat\n(d)O's Big sis",
		Answer:      0,
	},
}

type memAuthRepo struct {
	users         map[string]string // username -> password
	refreshTokens sync.Map
	groupItem     map[uint]model.GroupItem
	questions     map[string]model.QuestionSession
	roles         map[string]uint // username -> role
	userGroups    map[string]uint // username -> groupID
}

var mem_db = memAuthRepo{
	users: map[string]string{
		"user": "password123",
	},
	groupItem: map[uint]model.GroupItem{
		0: {
			GroupInv: map[uint]uint{
				0: 1,
				1: 1,
				3: 2,
			},
			GroupSlot: map[uint]uint{
				0: 1,
				2: 3,
				5: 0,
			},
		},
	},
	questions: map[string]model.QuestionSession{
		"0123456789abcdef0123456789abcdef": {
			ExpiresAt: time.Now().Add(15 * time.Minute),
			GroupID:   0,
			Question: model.Question{
				Description: "What is six times three?\n(a)6\n(b)18\n(c)9\n(d)12",
				Answer:      1,
			},
		},
	},
	roles: map[string]uint{
		"user": model.RoleTeacher,
	},
	userGroups: map[string]uint{
		"user": 0,
	},
}

type AuthRepo interface {
	ValidateCredentials(username, password string) (bool, error)
	StoreRefreshToken(token string) error
	ConsumeRefreshToken(token string) (bool, error)
	GetAllUsers() ([]string, error)
	GetRole(username string) (uint, error)
	CreateUser(username, password string, role uint) error
}

type authRepo struct{}

var authMu sync.RWMutex

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

func (_ *authRepo) GetAllUsers() ([]string, error) {
	users := make([]string, 0, len(mem_db.users))
	for username := range mem_db.users {
		users = append(users, username)
	}
	return users, nil
}

func (_ *authRepo) GetRole(username string) (uint, error) {
	authMu.RLock()
	defer authMu.RUnlock()
	return mem_db.roles[username], nil
}

func (_ *authRepo) CreateUser(username, password string, role uint) error {
	authMu.Lock()
	defer authMu.Unlock()
	if _, ok := mem_db.users[username]; ok {
		return apperr.ErrUserExists
	}
	mem_db.users[username] = password
	mem_db.roles[username] = role
	return nil
}

func InitAuthRepo() AuthRepo {
	return &authRepo{}
}
