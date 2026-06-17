package service

import (
	"encoding/json"
	"errors"
	"net/http"

	apperr "gb-api/internal/error"
	"gb-api/internal/repo"
)

type StudentSvc struct {
	repo  repo.StudentRepo
	users repo.UserRepo
}

func NewStudentSvc(r repo.StudentRepo, users repo.UserRepo) *StudentSvc {
	return &StudentSvc{repo: r, users: users}
}

// Create adds a new student. Only teachers/admins may create students.
func (s *StudentSvc) Create(accessToken, name, profilePicURL string) ([]byte, int, error) {
	if status, err := requireTeacher(s.users, accessToken); err != nil {
		return nil, status, err
	}
	id, err := s.repo.CreateStudent(name, profilePicURL)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	st, err := s.repo.GetStudent(id)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(st)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

// Update replaces every field of the student identified by id. Only teachers/admins may update.
func (s *StudentSvc) Update(accessToken string, id uint, name, profilePicURL string) ([]byte, int, error) {
	if status, err := requireTeacher(s.users, accessToken); err != nil {
		return nil, status, err
	}
	if err := s.repo.UpdateStudent(id, name, profilePicURL); err != nil {
		if errors.Is(err, apperr.ErrStudentNotFound) {
			return nil, http.StatusNotFound, err
		}
		return nil, http.StatusInternalServerError, err
	}
	st, err := s.repo.GetStudent(id)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(st)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

// Delete removes the student identified by id. Only teachers/admins may delete.
func (s *StudentSvc) Delete(accessToken string, id uint) ([]byte, int, error) {
	if status, err := requireTeacher(s.users, accessToken); err != nil {
		return nil, status, err
	}
	if err := s.repo.DeleteStudent(id); err != nil {
		if errors.Is(err, apperr.ErrStudentNotFound) {
			return nil, http.StatusNotFound, err
		}
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(map[string]bool{"deleted": true})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

// Get returns the student identified by id. Any authenticated user may read.
func (s *StudentSvc) Get(accessToken string, id uint) ([]byte, int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return nil, http.StatusUnauthorized, err
	}
	st, err := s.repo.GetStudent(id)
	if err != nil {
		if errors.Is(err, apperr.ErrStudentNotFound) {
			return nil, http.StatusNotFound, err
		}
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(st)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

// List returns every student. Any authenticated user may read.
func (s *StudentSvc) List(accessToken string) ([]byte, int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return nil, http.StatusUnauthorized, err
	}
	students, err := s.repo.GetAllStudents()
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(students)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}
