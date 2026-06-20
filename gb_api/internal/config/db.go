package config

// DatabaseURL is the Postgres connection string (libpq/pgx DSN or URL form).
var DatabaseURL = stringFromEnv("DATABASE_URL", "postgres://gb:gb@localhost:5432/gb?sslmode=disable")

// Admin seed credentials. The database is seeded with this account on startup so
// at least one admin can log in. Change these in production via env.
var (
	AdminUsername = stringFromEnv("ADMIN_USERNAME", "admin")
	AdminPassword = stringFromEnv("ADMIN_PASSWORD", "admin123")
)
