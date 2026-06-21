package repo

import "context"

// Per-slot attack block list
type BlockRepo interface {
	IsAttackBlocked(ownerID, slotID, attackerID uint) (bool, error)
	AddAttackBlock(ownerID, slotID, attackerID uint) error
	ClearAttackBlocks(ownerID, slotID uint) error
	ClearAllAttackBlocks() error                           // wipe every slot's blocklist (on NORMAL)
	QuerySlotBlocks(ownerID uint) (map[uint][]uint, error) // slot_id -> sorted attacker ids
}

type blockRepo struct{}

func (_ *blockRepo) IsAttackBlocked(ownerID, slotID, attackerID uint) (bool, error) {
	ctx := context.Background()
	var blocked bool
	err := pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM slot_attack_blocks
		               WHERE user_id = $1 AND slot_id = $2 AND attacker_id = $3)`,
		ownerID, slotID, attackerID,
	).Scan(&blocked)
	return blocked, err
}

func (_ *blockRepo) AddAttackBlock(ownerID, slotID, attackerID uint) error {
	ctx := context.Background()
	_, err := pool.Exec(ctx,
		`INSERT INTO slot_attack_blocks (user_id, slot_id, attacker_id) VALUES ($1, $2, $3)
		 ON CONFLICT DO NOTHING`,
		ownerID, slotID, attackerID,
	)
	return err
}

func (_ *blockRepo) ClearAttackBlocks(ownerID, slotID uint) error {
	ctx := context.Background()
	_, err := pool.Exec(ctx,
		`DELETE FROM slot_attack_blocks WHERE user_id = $1 AND slot_id = $2`, ownerID, slotID,
	)
	return err
}

func (_ *blockRepo) ClearAllAttackBlocks() error {
	ctx := context.Background()
	_, err := pool.Exec(ctx, `DELETE FROM slot_attack_blocks`)
	return err
}

func (_ *blockRepo) QuerySlotBlocks(ownerID uint) (map[uint][]uint, error) {
	ctx := context.Background()
	rows, err := pool.Query(ctx,
		`SELECT slot_id, attacker_id FROM slot_attack_blocks
		 WHERE user_id = $1 ORDER BY slot_id, attacker_id`, ownerID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make(map[uint][]uint)
	for rows.Next() {
		var slotID, attackerID uint
		if err := rows.Scan(&slotID, &attackerID); err != nil {
			return nil, err
		}
		out[slotID] = append(out[slotID], attackerID)
	}
	return out, rows.Err()
}

func InitBlockRepo() BlockRepo {
	return &blockRepo{}
}
