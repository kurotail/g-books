package repo

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	apperr "gb-api/internal/error"
	"gb-api/internal/model"

	"github.com/jackc/pgx/v5"
)

type BuildingRepo interface {
	CreateBuilding(name, layout string, typeAllowedSlot map[uint][]uint, difficultyType map[uint][]uint) (uint, error)
	UpdateBuilding(id uint, name, layout string, typeAllowedSlot map[uint][]uint, difficultyType map[uint][]uint) error
	GetBuilding(id uint) (model.Building, error)
	GetAllBuildings() ([]model.Building, error)
}

type buildingRepo struct{}

// marshalMap renders a map[uint][]uint as JSON text for a jsonb column. A nil map
// becomes "{}".
func marshalMap(m map[uint][]uint) (string, error) {
	if m == nil {
		return "{}", nil
	}
	b, err := json.Marshal(m)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// scanBuilding reads a building row, unmarshaling the two jsonb maps and applying
// the default "Building <id>" name.
func scanBuilding(row pgx.Row) (model.Building, error) {
	var (
		b                model.Building
		typeAllowed, dif []byte
	)
	if err := row.Scan(&b.ID, &b.Name, &b.Layout, &typeAllowed, &dif); err != nil {
		return model.Building{}, err
	}
	if err := json.Unmarshal(typeAllowed, &b.TypeAllowedSlot); err != nil {
		return model.Building{}, err
	}
	if err := json.Unmarshal(dif, &b.DifficultyType); err != nil {
		return model.Building{}, err
	}
	if b.Name == "" {
		b.Name = fmt.Sprintf("Building %d", b.ID)
	}
	return b, nil
}

func (_ *buildingRepo) CreateBuilding(name, layout string, typeAllowedSlot map[uint][]uint, difficultyType map[uint][]uint) (uint, error) {
	ctx := context.Background()
	tas, err := marshalMap(typeAllowedSlot)
	if err != nil {
		return 0, err
	}
	dt, err := marshalMap(difficultyType)
	if err != nil {
		return 0, err
	}
	var id uint
	err = pool.QueryRow(ctx,
		`INSERT INTO buildings (name, layout, type_allowed_slot, difficulty_type)
		 VALUES ($1, $2, $3, $4) RETURNING id`,
		name, layout, tas, dt,
	).Scan(&id)
	return id, err
}

func (_ *buildingRepo) UpdateBuilding(id uint, name, layout string, typeAllowedSlot map[uint][]uint, difficultyType map[uint][]uint) error {
	ctx := context.Background()
	tas, err := marshalMap(typeAllowedSlot)
	if err != nil {
		return err
	}
	dt, err := marshalMap(difficultyType)
	if err != nil {
		return err
	}
	tag, err := pool.Exec(ctx,
		`UPDATE buildings SET name = $2, layout = $3, type_allowed_slot = $4, difficulty_type = $5
		 WHERE id = $1`,
		id, name, layout, tas, dt,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return apperr.ErrBuildingNotFound
	}
	return nil
}

const selectBuildings = `SELECT id, name, layout, type_allowed_slot, difficulty_type FROM buildings`

func (_ *buildingRepo) GetBuilding(id uint) (model.Building, error) {
	ctx := context.Background()
	b, err := scanBuilding(pool.QueryRow(ctx, selectBuildings+` WHERE id = $1`, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return model.Building{}, apperr.ErrBuildingNotFound
	}
	if err != nil {
		return model.Building{}, err
	}
	return b, nil
}

func (_ *buildingRepo) GetAllBuildings() ([]model.Building, error) {
	ctx := context.Background()
	rows, err := pool.Query(ctx, selectBuildings+` ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	buildings := make([]model.Building, 0)
	for rows.Next() {
		b, err := scanBuilding(rows)
		if err != nil {
			return nil, err
		}
		buildings = append(buildings, b)
	}
	return buildings, rows.Err()
}

func InitBuildingRepo() BuildingRepo {
	return &buildingRepo{}
}
