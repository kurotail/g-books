package repo

import (
	"context"
	"errors"

	"gb-api/internal/model"

	"github.com/jackc/pgx/v5"
)

type InventoryRepo interface {
	QueryInventory(userID uint) ([]model.Item, error)            // owned (unslotted) items, sorted by id
	QuerySlotItems(userID uint) (map[uint]model.SlotItem, error) // slot_id -> hydrated slotted item
	QuerySlot(userID uint) (map[uint]int, error)                 // slot_id -> signed item_id (negative = broken)
	OwnedItem(userID, itemID uint) (model.Item, bool, error)     // the loose item + whether the user owns it
	AddInvItem(userID uint, itemID uint) error
	RemoveInvItem(userID uint, itemID uint) error
	SetSlot(userID uint, slotID uint, itemID int) error // itemID 0 clears the slot
}

type inventoryRepo struct{}

// OwnedItem returns the loose item the user holds and whether they own it, in a
// single query that joins user_inventory to items (no separate ownership probe).
func (_ *inventoryRepo) OwnedItem(userID, itemID uint) (model.Item, bool, error) {
	ctx := context.Background()
	var it model.Item
	err := pool.QueryRow(ctx,
		`SELECT i.id, i.type, i.question_id
		 FROM user_inventory ui JOIN items i ON i.id = ui.item_id
		 WHERE ui.user_id = $1 AND ui.item_id = $2`,
		userID, itemID,
	).Scan(&it.ItemID, &it.Type, &it.QuestionID)
	if errors.Is(err, pgx.ErrNoRows) {
		return model.Item{}, false, nil
	}
	if err != nil {
		return model.Item{}, false, err
	}
	return it, true, nil
}

func (_ *inventoryRepo) QueryInventory(userID uint) ([]model.Item, error) {
	ctx := context.Background()
	rows, err := pool.Query(ctx,
		`SELECT i.id, i.type, i.question_id
		 FROM user_inventory ui JOIN items i ON i.id = ui.item_id
		 WHERE ui.user_id = $1 ORDER BY i.id`, userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]model.Item, 0)
	for rows.Next() {
		var it model.Item
		if err := rows.Scan(&it.ItemID, &it.Type, &it.QuestionID); err != nil {
			return nil, err
		}
		items = append(items, it)
	}
	return items, rows.Err()
}

func (_ *inventoryRepo) QuerySlotItems(userID uint) (map[uint]model.SlotItem, error) {
	ctx := context.Background()
	rows, err := pool.Query(ctx,
		`SELECT us.slot_id, (us.item_id < 0) AS broken, i.id, i.type, i.question_id
		 FROM user_slots us JOIN items i ON i.id = abs(us.item_id)
		 WHERE us.user_id = $1`, userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make(map[uint]model.SlotItem)
	for rows.Next() {
		var (
			slotID uint
			si     model.SlotItem
		)
		if err := rows.Scan(&slotID, &si.Broken, &si.ItemID, &si.Type, &si.QuestionID); err != nil {
			return nil, err
		}
		out[slotID] = si
	}
	return out, rows.Err()
}

func (_ *inventoryRepo) QuerySlot(userID uint) (map[uint]int, error) {
	ctx := context.Background()
	rows, err := pool.Query(ctx,
		`SELECT slot_id, item_id FROM user_slots WHERE user_id = $1`, userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make(map[uint]int)
	for rows.Next() {
		var (
			slotID uint
			itemID int
		)
		if err := rows.Scan(&slotID, &itemID); err != nil {
			return nil, err
		}
		result[slotID] = itemID
	}
	return result, rows.Err()
}

func (_ *inventoryRepo) AddInvItem(userID uint, itemID uint) error {
	ctx := context.Background()
	_, err := pool.Exec(ctx,
		`INSERT INTO user_inventory (user_id, item_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
		userID, itemID,
	)
	return err
}

func (_ *inventoryRepo) RemoveInvItem(userID uint, itemID uint) error {
	ctx := context.Background()
	_, err := pool.Exec(ctx,
		`DELETE FROM user_inventory WHERE user_id = $1 AND item_id = $2`, userID, itemID,
	)
	// TODO: maybeDeleteItem(itemID) — once no user inventory and no slot references
	// an item, delete it from items. Left as a no-op for now.
	return err
}

func (_ *inventoryRepo) SetSlot(userID uint, slotID uint, itemID int) error {
	ctx := context.Background()
	if itemID == 0 {
		_, err := pool.Exec(ctx,
			`DELETE FROM user_slots WHERE user_id = $1 AND slot_id = $2`, userID, slotID,
		)
		return err
	}
	_, err := pool.Exec(ctx,
		`INSERT INTO user_slots (user_id, slot_id, item_id) VALUES ($1, $2, $3)
		 ON CONFLICT (user_id, slot_id) DO UPDATE SET item_id = EXCLUDED.item_id`,
		userID, slotID, itemID,
	)
	return err
}

func InitInventoryRepo() InventoryRepo {
	return &inventoryRepo{}
}
