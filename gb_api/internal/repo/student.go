package repo

import (
	"context"
	"errors"

	apperr "gb-api/internal/error"
	"gb-api/internal/model"

	"github.com/jackc/pgx/v5"
)

type StudentRepo interface {
	CreateStudent(name, profilePicURL string) (model.Student, error)
	UpdateStudent(id uint, name, profilePicURL string) (model.Student, error)
	GetStudent(id uint) (model.Student, error)
	GetAllStudents() ([]model.Student, error)
	ExistingStudentIDs(ids []uint) (map[uint]bool, error)
	DeleteStudent(id uint) error
}

type studentRepo struct{}

func (_ *studentRepo) CreateStudent(name, profilePicURL string) (model.Student, error) {
	ctx := context.Background()
	var s model.Student
	err := pool.QueryRow(ctx,
		`INSERT INTO students (name, profile_pic_url) VALUES ($1, $2)
		 RETURNING id, name, profile_pic_url`,
		name, profilePicURL,
	).Scan(&s.StudentID, &s.Name, &s.ProfilePicURL)
	if err != nil {
		return model.Student{}, err
	}
	return s, nil
}

// UpdateStudent updates a student and returns the updated row; ErrStudentNotFound
// when no student has that id.
func (_ *studentRepo) UpdateStudent(id uint, name, profilePicURL string) (model.Student, error) {
	ctx := context.Background()
	var s model.Student
	err := pool.QueryRow(ctx,
		`UPDATE students SET name = $2, profile_pic_url = $3 WHERE id = $1
		 RETURNING id, name, profile_pic_url`,
		id, name, profilePicURL,
	).Scan(&s.StudentID, &s.Name, &s.ProfilePicURL)
	if errors.Is(err, pgx.ErrNoRows) {
		return model.Student{}, apperr.ErrStudentNotFound
	}
	if err != nil {
		return model.Student{}, err
	}
	return s, nil
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

// ExistingStudentIDs returns the subset of ids that exist
func (_ *studentRepo) ExistingStudentIDs(ids []uint) (map[uint]bool, error) {
	ctx := context.Background()
	arg := make([]int64, len(ids))
	for i, id := range ids {
		arg[i] = int64(id)
	}
	rows, err := pool.Query(ctx, `SELECT id FROM students WHERE id = ANY($1)`, arg)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make(map[uint]bool, len(ids))
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out[uint(id)] = true
	}
	return out, rows.Err()
}

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
