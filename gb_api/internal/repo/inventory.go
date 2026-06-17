package repo

import (
	"sort"
)

type InventoryRepo interface {
	QueryInv(username string) ([]uint, error)        // owned (unslotted) item ids, sorted
	QuerySlot(username string) (map[uint]int, error) // slot_id -> signed item_id (negative = broken)
	AddInvItem(username string, itemID uint) error
	RemoveInvItem(username string, itemID uint) error
	SetSlot(username string, slotID uint, itemID int) error // itemID 0 clears the slot
}

type inventoryRepo struct{}

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

func (_ *inventoryRepo) QueryInv(username string) ([]uint, error) {
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

func (_ *inventoryRepo) QuerySlot(username string) (map[uint]int, error) {
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

func (_ *inventoryRepo) AddInvItem(username string, itemID uint) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	if u := userRow(username); u != nil {
		u.Inventory[itemID] = struct{}{}
	}
	return nil
}

func (_ *inventoryRepo) RemoveInvItem(username string, itemID uint) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	if u := userRow(username); u != nil {
		delete(u.Inventory, itemID)
	}
	// TODO: maybeDeleteItem(itemID) — once no user inventory and no slot references
	// an item, delete it from db.items. Left as a no-op for now.
	return nil
}

func (_ *inventoryRepo) SetSlot(username string, slotID uint, itemID int) error {
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

func InitInventoryRepo() InventoryRepo {
	return &inventoryRepo{}
}
