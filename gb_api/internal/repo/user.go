package repo

import (
	"context"
	"errors"

	apperr "gb-api/internal/error"
	"gb-api/internal/model"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// UserRepo is the user-account table: credentials, roles, and membership. It is
// shared by services that need to identify or authorize users.
type UserRepo interface {
	ValidateCredentials(username, password string) (bool, error)
	GetAllUsers() ([]model.User, error)
	GetUser(username string) (model.User, error)
	CreateUser(username, password string, role uint) error
	SetUserProfilePic(username, url string) error
	SetUserBuilding(username string, buildingID uint) error
	SetUserStudents(username string, studentIDs []uint) error
	DeleteUser(username string) (bool, error)
}

type userRepo struct{}

func (_ *userRepo) ValidateCredentials(username, password string) (bool, error) {
	ctx := context.Background()
	var stored string
	err := pool.QueryRow(ctx, `SELECT password FROM users WHERE username = $1`, username).Scan(&stored)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return checkPassword(stored, password), nil
}

// selectUsers is the shared projection: a user row plus its sorted student roster.
const selectUsers = `
	SELECT u.username, u.role, u.building_id, u.profile_pic_url,
	       COALESCE(array_agg(us.student_id ORDER BY us.student_id)
	                FILTER (WHERE us.student_id IS NOT NULL), '{}') AS students
	FROM users u
	LEFT JOIN user_students us ON us.username = u.username`

func scanUser(row pgx.Row) (model.User, error) {
	var u model.User
	var students []int64
	if err := row.Scan(&u.Username, &u.Role, &u.BuildingID, &u.ProfilePicURL, &students); err != nil {
		return model.User{}, err
	}
	u.Students = make([]uint, len(students))
	for i, id := range students {
		u.Students[i] = uint(id)
	}
	return u, nil
}

func (_ *userRepo) GetAllUsers() ([]model.User, error) {
	ctx := context.Background()
	rows, err := pool.Query(ctx, selectUsers+` GROUP BY u.username`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	users := make([]model.User, 0)
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, rows.Err()
}

func (_ *userRepo) GetUser(username string) (model.User, error) {
	ctx := context.Background()
	row := pool.QueryRow(ctx, selectUsers+` WHERE u.username = $1 GROUP BY u.username`, username)
	u, err := scanUser(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return model.User{}, apperr.ErrUserNotFound
	}
	if err != nil {
		return model.User{}, err
	}
	return u, nil
}

func (_ *userRepo) SetUserProfilePic(username, url string) error {
	return updateUserField(`UPDATE users SET profile_pic_url = $2 WHERE username = $1`, username, url)
}

func (_ *userRepo) SetUserBuilding(username string, buildingID uint) error {
	return updateUserField(`UPDATE users SET building_id = $2 WHERE username = $1`, username, buildingID)
}

// updateUserField runs a single-column UPDATE keyed by username, returning
// ErrUserNotFound when no row matched.
func updateUserField(sql, username string, value any) error {
	ctx := context.Background()
	tag, err := pool.Exec(ctx, sql, username, value)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return apperr.ErrUserNotFound
	}
	return nil
}

// SetUserStudents replaces the user's assigned-student set with the given ids.
func (_ *userRepo) SetUserStudents(username string, studentIDs []uint) error {
	ctx := context.Background()
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var exists bool
	if err := tx.QueryRow(ctx, `SELECT true FROM users WHERE username = $1`, username).Scan(&exists); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return apperr.ErrUserNotFound
		}
		return err
	}

	if _, err := tx.Exec(ctx, `DELETE FROM user_students WHERE username = $1`, username); err != nil {
		return err
	}
	for _, id := range studentIDs {
		if _, err := tx.Exec(ctx,
			`INSERT INTO user_students (username, student_id) VALUES ($1, $2)
			 ON CONFLICT DO NOTHING`, username, id,
		); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

func (_ *userRepo) CreateUser(username, password string, role uint) error {
	ctx := context.Background()
	hash, err := hashPassword(password)
	if err != nil {
		return err
	}
	_, err = pool.Exec(ctx,
		`INSERT INTO users (username, password, role) VALUES ($1, $2, $3)`,
		username, hash, role,
	)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" { // unique_violation
		return apperr.ErrUserExists
	}
	return err
}

// DeleteUser removes a user. The bool reports whether the user existed.
func (_ *userRepo) DeleteUser(username string) (bool, error) {
	ctx := context.Background()
	tag, err := pool.Exec(ctx, `DELETE FROM users WHERE username = $1`, username)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

func InitUserRepo() UserRepo {
	return &userRepo{}
}
