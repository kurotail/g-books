package repo

import (
	"sync"

	apperr "gb-api/internal/error"
)

type ItemRepo interface {
	QueryInv(groupID uint) (map[uint]uint, error)
	QuerySlot(groupID uint) (map[uint]uint, error)
	ChangeInv(groupID, itemID uint, delta int) error
	SetSlot(groupID, slotID, itemID uint) error
}

type itemRepo struct{}

var itemMu sync.RWMutex

func (_ *itemRepo) QueryInv(groupID uint) (map[uint]uint, error) {
	itemMu.RLock()
	defer itemMu.RUnlock()
	inv := mem_db.groupItem[groupID].GroupInv
	result := make(map[uint]uint, len(inv))
	for k, v := range inv {
		result[k] = v
	}
	return result, nil
}

func (_ *itemRepo) QuerySlot(groupID uint) (map[uint]uint, error) {
	itemMu.RLock()
	defer itemMu.RUnlock()
	slot := mem_db.groupItem[groupID].GroupSlot
	result := make(map[uint]uint, len(slot))
	for k, v := range slot {
		result[k] = v
	}
	return result, nil
}

// ChangeInv adjusts itemID's count in a group's inventory by delta (which may be
// negative), atomically under the write lock. A decrement that would drop the
// count below zero is rejected with ErrInsufficientStock; reaching exactly zero
// removes the item.
func (_ *itemRepo) ChangeInv(groupID, itemID uint, delta int) error {
	itemMu.Lock()
	defer itemMu.Unlock()
	group := mem_db.groupItem[groupID]
	if group.GroupInv == nil {
		group.GroupInv = make(map[uint]uint)
	}
	next := int(group.GroupInv[itemID]) + delta
	if next < 0 {
		return apperr.ErrInsufficientStock
	}
	if next == 0 {
		delete(group.GroupInv, itemID)
	} else {
		group.GroupInv[itemID] = uint(next)
	}
	mem_db.groupItem[groupID] = group
	return nil
}

func (_ *itemRepo) SetSlot(groupID, slotID, itemID uint) error {
	itemMu.Lock()
	defer itemMu.Unlock()
	group := mem_db.groupItem[groupID]
	if itemID == 0 {
		delete(group.GroupSlot, slotID)
		return nil
	}
	if group.GroupSlot == nil {
		group.GroupSlot = make(map[uint]uint)
	}
	group.GroupSlot[slotID] = itemID
	mem_db.groupItem[groupID] = group
	return nil
}

func InitItemRepo() ItemRepo {
	return &itemRepo{}
}
