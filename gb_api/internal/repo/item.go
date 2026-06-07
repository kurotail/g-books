package repo

import (
	"sort"

	"gb-api/internal/model"
)

type ItemRepo interface {
	QueryInv(groupID uint) ([]uint, error)        // owned (unslotted) item ids, sorted
	QuerySlot(groupID uint) (map[uint]int, error) // slot_id -> signed item_id (negative = broken)
	GetItem(itemID uint) (model.Item, bool, error)
	AddInvItem(groupID, itemID uint) error
	RemoveInvItem(groupID, itemID uint) error
	SetSlot(groupID, slotID uint, itemID int) error // itemID 0 clears the slot
}

type itemRepo struct{}

// group returns the group row for groupID, creating an empty one if absent.
// Callers must hold db.mu.Lock.
func group(groupID uint) *Group {
	g := db.groups[groupID]
	if g == nil {
		g = &Group{
			ID:        groupID,
			Inventory: make(map[uint]struct{}),
			Slots:     make(map[uint]int),
		}
		db.groups[groupID] = g
	}
	return g
}

func (_ *itemRepo) QueryInv(groupID uint) ([]uint, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	var ids []uint
	if g := db.groups[groupID]; g != nil {
		ids = make([]uint, 0, len(g.Inventory))
		for id := range g.Inventory {
			ids = append(ids, id)
		}
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	return ids, nil
}

func (_ *itemRepo) QuerySlot(groupID uint) (map[uint]int, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	result := make(map[uint]int)
	if g := db.groups[groupID]; g != nil {
		for k, v := range g.Slots {
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

func (_ *itemRepo) AddInvItem(groupID, itemID uint) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	group(groupID).Inventory[itemID] = struct{}{}
	return nil
}

func (_ *itemRepo) RemoveInvItem(groupID, itemID uint) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	delete(group(groupID).Inventory, itemID)
	// TODO: maybeDeleteItem(itemID) — once no group inventory and no slot references
	// an item, delete it from db.items. Left as a no-op for now.
	return nil
}

func (_ *itemRepo) SetSlot(groupID, slotID uint, itemID int) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	g := group(groupID)
	if itemID == 0 {
		delete(g.Slots, slotID)
	} else {
		g.Slots[slotID] = itemID
	}
	return nil
}

func InitItemRepo() ItemRepo {
	return &itemRepo{}
}
