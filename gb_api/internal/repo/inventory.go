package repo

import (
	"context"
)

type InventoryRepo interface {
	QueryInv(username string) ([]uint, error)        // owned (unslotted) item ids, sorted
	QuerySlot(username string) (map[uint]int, error) // slot_id -> signed item_id (negative = broken)
	AddInvItem(username string, itemID uint) error
	RemoveInvItem(username string, itemID uint) error
	SetSlot(username string, slotID uint, itemID int) error // itemID 0 clears the slot
}

type inventoryRepo struct{}

func (_ *inventoryRepo) QueryInv(username string) ([]uint, error) {
	ctx := context.Background()
	rows, err := pool.Query(ctx,
		`SELECT item_id FROM user_inventory WHERE username = $1 ORDER BY item_id`, username,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	ids := make([]uint, 0)
	for rows.Next() {
		var id uint
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func (_ *inventoryRepo) QuerySlot(username string) (map[uint]int, error) {
	ctx := context.Background()
	rows, err := pool.Query(ctx,
		`SELECT slot_id, item_id FROM user_slots WHERE username = $1`, username,
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

func (_ *inventoryRepo) AddInvItem(username string, itemID uint) error {
	ctx := context.Background()
	_, err := pool.Exec(ctx,
		`INSERT INTO user_inventory (username, item_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
		username, itemID,
	)
	return err
}

func (_ *inventoryRepo) RemoveInvItem(username string, itemID uint) error {
	ctx := context.Background()
	_, err := pool.Exec(ctx,
		`DELETE FROM user_inventory WHERE username = $1 AND item_id = $2`, username, itemID,
	)
	// TODO: maybeDeleteItem(itemID) — once no user inventory and no slot references
	// an item, delete it from items. Left as a no-op for now.
	return err
}

func (_ *inventoryRepo) SetSlot(username string, slotID uint, itemID int) error {
	ctx := context.Background()
	if itemID == 0 {
		_, err := pool.Exec(ctx,
			`DELETE FROM user_slots WHERE username = $1 AND slot_id = $2`, username, slotID,
		)
		return err
	}
	_, err := pool.Exec(ctx,
		`INSERT INTO user_slots (username, slot_id, item_id) VALUES ($1, $2, $3)
		 ON CONFLICT (username, slot_id) DO UPDATE SET item_id = EXCLUDED.item_id`,
		username, slotID, itemID,
	)
	return err
}

func InitInventoryRepo() InventoryRepo {
	return &inventoryRepo{}
}
