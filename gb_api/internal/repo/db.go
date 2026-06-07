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
	Name       string            // empty = use the default "Group <id>"
	BuildingID uint              // FK -> buildings; 0 = no building assigned
	Inventory  map[uint]struct{} // set of owned (unslotted) item_ids
	Slots      map[uint]int      // slot_id -> signed item_id (negative = broken)
}

// Building is a row in the buildings table. Primary key: ID.
type Building struct {
	ID              uint
	Name            string          // empty = use the default "Building <id>"
	Layout          string          // frontend-specific JSON blob, stored verbatim
	TypeAllowedSlot map[uint][]uint // type -> allowed slot_ids
	DifficultyType  map[uint][]uint // difficulty -> types
}

// Database is an in-memory, relationally-structured store: a set of tables keyed
// by primary key, guarded by one RWMutex (a single serialized "connection").
type Database struct {
	mu             sync.RWMutex
	users          map[string]*User                 // PK: username
	groups         map[uint]*Group                  // PK: id
	buildings      map[uint]*Building               // PK: id
	items          map[uint]model.Item              // PK: item id
	sessions       map[string]model.QuestionSession // PK: session_id
	refreshTokens  map[string]struct{}              // PK: jti (refresh token id)
	questions      map[uint]model.Question          // PK: question id; the pool sessions are drawn from
	nextQuestionID uint                             // next id to assign on insert
	nextBuildingID uint                             // next id to assign on insert
	nextItemID     uint                             // next id to assign on insert
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
				Inventory: map[uint]struct{}{1: {}, 2: {}, 4: {}},
				Slots:     map[uint]int{0: 3},
			},
		},
		buildings: map[uint]*Building{
			1: {
				ID:              1,
				Name:            "Library",
				Layout:          "{}",
				TypeAllowedSlot: map[uint][]uint{10: {0, 1}, 20: {2}},
				DifficultyType:  map[uint][]uint{1: {10}, 2: {20}},
			},
		},
		items: map[uint]model.Item{
			1: {ItemID: 1, Type: 10, QuestionID: 1},
			2: {ItemID: 2, Type: 20, QuestionID: 2},
			3: {ItemID: 3, Type: 10},
			4: {ItemID: 4, Type: 30},
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
				Difficulty:  1,
				Area:        1,
			},
			2: {
				Description: "Who is F\n(a)HRM\n(b)M's child\n(c)White cat\n(d)O's Big sis",
				Answer:      0,
				Difficulty:  2,
				Area:        2,
			},
		},
		nextQuestionID: 3,
		nextBuildingID: 2,
		nextItemID:     5,
	}
}
