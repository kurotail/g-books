package repo

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
)

// RefreshTokenRepo is the refresh-token store, keyed by jti. A token is a live,
// single-use handle: StoreRefreshToken registers it, ConsumeRefreshToken
// atomically validates and removes it.
type RefreshTokenRepo interface {
	StoreRefreshToken(jti string) error
	ConsumeRefreshToken(jti string) (bool, error)
}

type refreshTokenRepo struct{}

func (_ *refreshTokenRepo) StoreRefreshToken(jti string) error {
	ctx := context.Background()
	_, err := pool.Exec(ctx,
		`INSERT INTO refresh_tokens (jti) VALUES ($1) ON CONFLICT DO NOTHING`, jti,
	)
	return err
}

func (_ *refreshTokenRepo) ConsumeRefreshToken(jti string) (bool, error) {
	ctx := context.Background()
	var got string
	err := pool.QueryRow(ctx,
		`DELETE FROM refresh_tokens WHERE jti = $1 RETURNING jti`, jti,
	).Scan(&got)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

func InitRefreshTokenRepo() RefreshTokenRepo {
	return &refreshTokenRepo{}
}
