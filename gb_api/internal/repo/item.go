package repo

import (
	"sort"

	"gb-api/internal/model"
)

type ItemRepo interface {
	QueryInv(username string) ([]uint, error)        // owned (unslotted) item ids, sorted
	QuerySlot(username string) (map[uint]int, error) // slot_id -> signed item_id (negative = broken)
	GetItem(itemID uint) (model.Item, bool, error)
	CreateItem(itemType, questionID uint) (uint, error)
	AddInvItem(username string, itemID uint) error
	RemoveInvItem(username string, itemID uint) error
	SetSlot(username string, slotID uint, itemID int) error // itemID 0 clears the slot
}

type itemRepo struct{}

// userRow returns the user row for username and lazily initializes its Inventory/Slots
// maps. It returns nil if the user does not exist. Callers must hold db.mu.Lock.
func userRow(username string) *User {
	u := db.users[username]
	if u == nil {
		return nil
	}
	if u.Inventory == nil {
		u.Inventory = make(map[uint]struct{})
	}
	if u.Slots == nil {
		u.Slots = make(map[uint]int)
	}
	return u
}

func (_ *itemRepo) QueryInv(username string) ([]uint, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	var ids []uint
	if u := db.users[username]; u != nil {
		ids = make([]uint, 0, len(u.Inventory))
		for id := range u.Inventory {
			ids = append(ids, id)
		}
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	return ids, nil
}

func (_ *itemRepo) QuerySlot(username string) (map[uint]int, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	result := make(map[uint]int)
	if u := db.users[username]; u != nil {
		for k, v := range u.Slots {
			result[k] = v
		}
	}
	return result, nil
}

func (_ *itemRepo) GetItem(itemID uint) (model.Item, bool, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	it, ok := db.items[itemID]
	return it, ok, nil
}

// CreateItem inserts a new item with the given type and question, returning its id.
func (_ *itemRepo) CreateItem(itemType, questionID uint) (uint, error) {
	db.mu.Lock()
	defer db.mu.Unlock()
	id := db.nextItemID
	db.nextItemID++
	db.items[id] = model.Item{ItemID: id, Type: itemType, QuestionID: questionID}
	return id, nil
}

func (_ *itemRepo) AddInvItem(username string, itemID uint) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	if u := userRow(username); u != nil {
		u.Inventory[itemID] = struct{}{}
	}
	return nil
}

func (_ *itemRepo) RemoveInvItem(username string, itemID uint) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	if u := userRow(username); u != nil {
		delete(u.Inventory, itemID)
	}
	// TODO: maybeDeleteItem(itemID) — once no user inventory and no slot references
	// an item, delete it from db.items. Left as a no-op for now.
	return nil
}

func (_ *itemRepo) SetSlot(username string, slotID uint, itemID int) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	u := userRow(username)
	if u == nil {
		return nil
	}
	if itemID == 0 {
		delete(u.Slots, slotID)
	} else {
		u.Slots[slotID] = itemID
	}
	return nil
}

func InitItemRepo() ItemRepo {
	return &itemRepo{}
}
