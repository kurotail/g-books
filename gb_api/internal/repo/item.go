package repo

import "sync"

type ItemRepo interface {
	QueryInv(groupID uint) (map[uint]uint, error)
	QuerySlot(groupID uint) (map[uint]uint, error)
	SetInv(groupID, itemID, itemCount uint) error
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

func (_ *itemRepo) SetInv(groupID, itemID, itemCount uint) error {
	itemMu.Lock()
	defer itemMu.Unlock()
	if itemCount == 0 {
		delete(mem_db.groupInv, itemID)
	} else {
		mem_db.groupInv[itemID] = itemCount
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
