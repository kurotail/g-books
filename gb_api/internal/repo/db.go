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
	GroupID  uint // FK -> groups; 0 = not a member of any group
}

// Group is a row in the groups table. Primary key: ID.
type Group struct {
	ID         uint
	Name       string        // empty = use the default "Group <id>"
	BuildingID uint          // FK -> buildings; 0 = no building assigned
	Inventory  map[uint]uint // item_id -> count
	Slots      map[uint]int  // slot_id -> item_id
}

// Database is an in-memory, relationally-structured store: a set of tables keyed
// by primary key, guarded by one RWMutex (a single serialized "connection").
type Database struct {
	mu             sync.RWMutex
	users          map[string]*User                 // PK: username
	groups         map[uint]*Group                  // PK: id
	sessions       map[string]model.QuestionSession // PK: session_id
	refreshTokens  map[string]struct{}              // PK: jti (refresh token id)
	questions      map[uint]model.Question          // PK: question id; the pool sessions are drawn from
	nextQuestionID uint                             // next id to assign on insert
}

// db is the process-wide store. It replaces the former denormalized mem_db.
var db = newDatabase()

func newDatabase() *Database {
	return &Database{
		users: map[string]*User{
			"user": {
				Username: "user",
				Password: "password123",
				Role:     model.RoleTeacher,
				GroupID:  1,
			},
		},
		groups: map[uint]*Group{
			1: {
				ID:        1,
				Inventory: map[uint]uint{1: 1, 2: 1, 3: 2},
				Slots:     map[uint]int{0: 1, 2: 3},
			},
		},
		sessions: map[string]model.QuestionSession{
			"0123456789abcdef0123456789abcdef": {
				ExpiresAt: time.Now().Add(15 * time.Minute),
				GroupID:   1,
				Question: model.Question{
					Description: "What is six times three?\n(a)6\n(b)18\n(c)9\n(d)12",
					Answer:      1,
				},
			},
		},
		refreshTokens: map[string]struct{}{},
		questions: map[uint]model.Question{
			1: {
				Description: "What is six times three?\n(a)6\n(b)18\n(c)9\n(d)12",
				Answer:      1,
			},
			2: {
				Description: "Who is F\n(a)HRM\n(b)M's child\n(c)White cat\n(d)O's Big sis",
				Answer:      0,
			},
		},
		nextQuestionID: 3,
	}
}
