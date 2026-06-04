package repo

import (
	"sync"
	"time"

	"gb-api/internal/model"
)

// User is a row in the users table. Primary key: Username.
type User struct {
	Username string
	Password string
	Role     uint
	GroupID  *uint // nullable FK -> groups; nil = not a member of any group
}

// Group is a row in the groups table. Primary key: ID.
type Group struct {
	ID        uint
	Inventory map[uint]uint // item_id -> count
	Slots     map[uint]uint // slot_id -> item_id
}

// Database is an in-memory, relationally-structured store: a set of tables keyed
// by primary key, guarded by one RWMutex (a single serialized "connection").
type Database struct {
	mu            sync.RWMutex
	users         map[string]*User                 // PK: username
	groups        map[uint]*Group                  // PK: id
	sessions      map[string]model.QuestionSession // PK: session_id
	refreshTokens map[string]struct{}              // PK: token
}

// questionList is the reference set of questions sessions are drawn from.
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

// db is the process-wide store. It replaces the former denormalized mem_db.
var db = newDatabase()

func newDatabase() *Database {
	group0 := uint(0)
	return &Database{
		users: map[string]*User{
			"user": {
				Username: "user",
				Password: "password123",
				Role:     model.RoleTeacher,
				GroupID:  &group0,
			},
		},
		groups: map[uint]*Group{
			0: {
				ID:        0,
				Inventory: map[uint]uint{0: 1, 1: 1, 3: 2},
				Slots:     map[uint]uint{0: 1, 2: 3, 5: 0},
			},
		},
		sessions: map[string]model.QuestionSession{
			"0123456789abcdef0123456789abcdef": {
				ExpiresAt: time.Now().Add(15 * time.Minute),
				GroupID:   0,
				Question: model.Question{
					Description: "What is six times three?\n(a)6\n(b)18\n(c)9\n(d)12",
					Answer:      1,
				},
			},
		},
		refreshTokens: map[string]struct{}{},
	}
}

// roleOf returns a user's role, defaulting unknown users to RoleStudent (0).
// Callers must hold at least db.mu.RLock.
func roleOf(username string) uint {
	if u := db.users[username]; u != nil {
		return u.Role
	}
	return 0
}
