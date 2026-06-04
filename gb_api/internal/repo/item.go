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
	result := make(map[uint]uint, len(mem_db.groupInv))
	for k, v := range mem_db.groupInv {
		result[k] = v
	}
	return result, nil
}

func (_ *itemRepo) QuerySlot(groupID uint) (map[uint]uint, error) {
	itemMu.RLock()
	defer itemMu.RUnlock()
	result := make(map[uint]uint, len(mem_db.groupSlot))
	for k, v := range mem_db.groupSlot {
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
	next := int(mem_db.groupInv[itemID]) + delta
	if next < 0 {
		return apperr.ErrInsufficientStock
	}
	if next == 0 {
		delete(mem_db.groupInv, itemID)
	} else {
		mem_db.groupInv[itemID] = uint(next)
	}
	return nil
}

func (_ *itemRepo) SetSlot(groupID, slotID, itemID uint) error {
	itemMu.Lock()
	defer itemMu.Unlock()
	if itemID == 0 {
		delete(mem_db.groupSlot, slotID)
	} else {
		mem_db.groupSlot[slotID] = itemID
	}
	return nil
}

func InitItemRepo() ItemRepo {
	return &itemRepo{}
}
