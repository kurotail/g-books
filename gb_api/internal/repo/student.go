package repo

import (
	apperr "gb-api/internal/error"
	"gb-api/internal/model"
)

type StudentRepo interface {
	CreateStudent(name, profilePicURL string) (uint, error)
	UpdateStudent(id uint, name, profilePicURL string) error
	GetStudent(id uint) (model.Student, error)
	GetAllStudents() ([]model.Student, error)
	DeleteStudent(id uint) error
}

type studentRepo struct{}

func (_ *studentRepo) CreateStudent(name, profilePicURL string) (uint, error) {
	db.mu.Lock()
	defer db.mu.Unlock()
	id := db.nextStudentID
	db.nextStudentID++
	db.students[id] = model.Student{StudentID: id, Name: name, ProfilePicURL: profilePicURL}
	return id, nil
}

func (_ *studentRepo) UpdateStudent(id uint, name, profilePicURL string) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	if _, ok := db.students[id]; !ok {
		return apperr.ErrStudentNotFound
	}
	db.students[id] = model.Student{StudentID: id, Name: name, ProfilePicURL: profilePicURL}
	return nil
}

func (_ *studentRepo) GetStudent(id uint) (model.Student, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	s, ok := db.students[id]
	if !ok {
		return model.Student{}, apperr.ErrStudentNotFound
	}
	return s, nil
}

func (_ *studentRepo) GetAllStudents() ([]model.Student, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	students := make([]model.Student, 0, len(db.students))
	for _, s := range db.students {
		students = append(students, s)
	}
	return students, nil
}

func (_ *studentRepo) DeleteStudent(id uint) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	if _, ok := db.students[id]; !ok {
		return apperr.ErrStudentNotFound
	}
	delete(db.students, id)
	return nil
}

func InitStudentRepo() StudentRepo {
	return &studentRepo{}
}
