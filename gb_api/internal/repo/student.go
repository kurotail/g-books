package repo

import (
	"context"
	"errors"

	apperr "gb-api/internal/error"
	"gb-api/internal/model"

	"github.com/jackc/pgx/v5"
)

type StudentRepo interface {
	CreateStudent(name, profilePicURL string) (uint, error)
	UpdateStudent(id uint, name, profilePicURL string) error
	GetStudent(id uint) (model.Student, error)
	GetAllStudents() ([]model.Student, error)
	DeleteStudent(id uint) error
}

type studentRepo struct{}

// CreateStudent inserts a student with a server-assigned id and returns it.
func (_ *studentRepo) CreateStudent(name, profilePicURL string) (uint, error) {
	ctx := context.Background()
	var id uint
	err := pool.QueryRow(ctx,
		`INSERT INTO students (name, profile_pic_url) VALUES ($1, $2) RETURNING id`,
		name, profilePicURL,
	).Scan(&id)
	if err != nil {
		return 0, err
	}
	return id, nil
}

func (_ *studentRepo) UpdateStudent(id uint, name, profilePicURL string) error {
	ctx := context.Background()
	tag, err := pool.Exec(ctx,
		`UPDATE students SET name = $2, profile_pic_url = $3 WHERE id = $1`,
		id, name, profilePicURL,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return apperr.ErrStudentNotFound
	}
	return nil
}

func (_ *studentRepo) GetStudent(id uint) (model.Student, error) {
	ctx := context.Background()
	var s model.Student
	err := pool.QueryRow(ctx,
		`SELECT id, name, profile_pic_url FROM students WHERE id = $1`, id,
	).Scan(&s.StudentID, &s.Name, &s.ProfilePicURL)
	if errors.Is(err, pgx.ErrNoRows) {
		return model.Student{}, apperr.ErrStudentNotFound
	}
	if err != nil {
		return model.Student{}, err
	}
	return s, nil
}

func (_ *studentRepo) GetAllStudents() ([]model.Student, error) {
	ctx := context.Background()
	rows, err := pool.Query(ctx, `SELECT id, name, profile_pic_url FROM students ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	students := make([]model.Student, 0)
	for rows.Next() {
		var s model.Student
		if err := rows.Scan(&s.StudentID, &s.Name, &s.ProfilePicURL); err != nil {
			return nil, err
		}
		students = append(students, s)
	}
	return students, rows.Err()
}

// DeleteStudent removes a student. Roster references are removed by the
// user_students FK ON DELETE CASCADE.
func (_ *studentRepo) DeleteStudent(id uint) error {
	ctx := context.Background()
	tag, err := pool.Exec(ctx, `DELETE FROM students WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return apperr.ErrStudentNotFound
	}
	return nil
}

func InitStudentRepo() StudentRepo {
	return &studentRepo{}
}
