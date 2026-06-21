package repo

import (
	"context"
	"fmt"
	"time"

	"gb-api/internal/logger"
	"gb-api/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Pool is the process-wide Postgres connection Pool. It replaces the former
// in-memory store. Init must be called once at startup before any repo is used.
var pool *pgxpool.Pool

// Init opens the connection pool and seeds the admin account. The schema is
// created by postgres/init.sql when the database is first initialized. It retries
// the initial connection for a short while so it tolerates Postgres still coming
// up alongside the API container.
func Init(ctx context.Context, dsn, adminUser, adminPass string) error {
	p, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return fmt.Errorf("repo: open pool: %w", err)
	}

	// Wait for the database to accept connections (up to ~30s).
	var pingErr error
	for range 30 {
		if pingErr = p.Ping(ctx); pingErr == nil {
			break
		}
		logger.L.Info("repo: waiting for database...")
		select {
		case <-ctx.Done():
			p.Close()
			return ctx.Err()
		case <-time.After(time.Second):
		}
	}
	if pingErr != nil {
		p.Close()
		return fmt.Errorf("repo: database unreachable: %w", pingErr)
	}

	// Seed the admin account (idempotent). The password is bcrypt-hashed; the hash is
	// only inserted on first run (ON CONFLICT DO NOTHING leaves an existing admin alone).
	adminHash, err := hashPassword(adminPass)
	if err != nil {
		p.Close()
		return fmt.Errorf("repo: hash admin password: %w", err)
	}
	if _, err := p.Exec(ctx,
		`INSERT INTO users (username, password, role, display_name) VALUES ($1, $2, $3, $1)
		 ON CONFLICT (username) DO NOTHING`,
		adminUser, adminHash, model.RoleAdmin,
	); err != nil {
		p.Close()
		return fmt.Errorf("repo: seed admin: %w", err)
	}

	pool = p
	logger.L.Info("repo: database ready")
	return nil
}

// Close releases the connection pool.
func Close() {
	if pool != nil {
		pool.Close()
	}
}
