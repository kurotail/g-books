package repo

import (
	"context"
	"errors"

	"gb-api/internal/model"

	"github.com/jackc/pgx/v5"
)

type ItemRepo interface {
	GetItem(itemID uint) (model.Item, bool, error)
	CreateItem(itemType, questionID uint) (uint, error)
}

type itemRepo struct{}

func (_ *itemRepo) GetItem(itemID uint) (model.Item, bool, error) {
	ctx := context.Background()
	var it model.Item
	err := pool.QueryRow(ctx,
		`SELECT id, type, question_id FROM items WHERE id = $1`, itemID,
	).Scan(&it.ItemID, &it.Type, &it.QuestionID)
	if errors.Is(err, pgx.ErrNoRows) {
		return model.Item{}, false, nil
	}
	if err != nil {
		return model.Item{}, false, err
	}
	return it, true, nil
}

// CreateItem inserts a new item with the given type and question, returning its id.
func (_ *itemRepo) CreateItem(itemType, questionID uint) (uint, error) {
	ctx := context.Background()
	var id uint
	err := pool.QueryRow(ctx,
		`INSERT INTO items (type, question_id) VALUES ($1, $2) RETURNING id`,
		itemType, questionID,
	).Scan(&id)
	return id, err
}

func InitItemRepo() ItemRepo {
	return &itemRepo{}
}
