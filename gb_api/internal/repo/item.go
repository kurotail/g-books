package repo

import (
	apperr "gb-api/internal/error"
)

type ItemRepo interface {
	QueryInv(groupID uint) (map[uint]uint, error)
	QuerySlot(groupID uint) (map[uint]uint, error)
	ChangeInv(groupID, itemID uint, delta int) error
	SetSlot(groupID, slotID, itemID uint) error
}

type itemRepo struct{}

// group returns the group row for groupID, creating an empty one if absent.
// Callers must hold db.mu.Lock.
func group(groupID uint) *Group {
	g := db.groups[groupID]
	if g == nil {
		g = &Group{
			ID:        groupID,
			Inventory: make(map[uint]uint),
			Slots:     make(map[uint]uint),
		}
		db.groups[groupID] = g
	}
	return g
}

func (_ *itemRepo) QueryInv(groupID uint) (map[uint]uint, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	result := make(map[uint]uint)
	if g := db.groups[groupID]; g != nil {
		for k, v := range g.Inventory {
			result[k] = v
		}
	}
	return result, nil
}

func (_ *itemRepo) QuerySlot(groupID uint) (map[uint]uint, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	result := make(map[uint]uint)
	if g := db.groups[groupID]; g != nil {
		for k, v := range g.Slots {
			result[k] = v
		}
	}
	return result, nil
}

// ChangeInv adjusts itemID's count in a group's inventory by delta (which may be
// negative), atomically under the write lock. A decrement that would drop the
// count below zero is rejected with ErrInsufficientStock; reaching exactly zero
// removes the item.
func (_ *itemRepo) ChangeInv(groupID, itemID uint, delta int) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	g := group(groupID)
	next := int(g.Inventory[itemID]) + delta
	if next < 0 {
		return apperr.ErrInsufficientStock
	}
	if next == 0 {
		delete(g.Inventory, itemID)
	} else {
		g.Inventory[itemID] = uint(next)
	}
	return nil
}

func (_ *itemRepo) SetSlot(groupID, slotID, itemID uint) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	g := group(groupID)
	if itemID == 0 {
		delete(g.Slots, slotID)
		return nil
	}
	g.Slots[slotID] = itemID
	return nil
}

func InitItemRepo() ItemRepo {
	return &itemRepo{}
}
