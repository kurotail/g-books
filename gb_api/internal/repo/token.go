package repo

// RefreshTokenRepo is the refresh-token store, keyed by jti. A token is a live,
// single-use handle: StoreRefreshToken registers it, ConsumeRefreshToken
// atomically validates and removes it.
type RefreshTokenRepo interface {
	StoreRefreshToken(jti string) error
	ConsumeRefreshToken(jti string) (bool, error)
}

type refreshTokenRepo struct{}

func (_ *refreshTokenRepo) StoreRefreshToken(jti string) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	db.refreshTokens[jti] = struct{}{}
	return nil
}

func (_ *refreshTokenRepo) ConsumeRefreshToken(jti string) (bool, error) {
	db.mu.Lock()
	defer db.mu.Unlock()
	if _, ok := db.refreshTokens[jti]; ok {
		delete(db.refreshTokens, jti)
		return true, nil
	}
	return false, nil
}

func InitRefreshTokenRepo() RefreshTokenRepo {
	return &refreshTokenRepo{}
}
