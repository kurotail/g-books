package repo

import (
	"gb-api/internal/model"
)

type ItemRepo interface {
	GetItem(itemID uint) (model.Item, bool, error)
	CreateItem(itemType, questionID uint) (uint, error)
}

type itemRepo struct{}

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

func InitItemRepo() ItemRepo {
	return &itemRepo{}
}
