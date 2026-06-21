package service

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"slices"

	apperr "gb-api/internal/error"
	"gb-api/internal/model"
	"gb-api/internal/repo"
)

type StudentSvc struct {
	repo  repo.StudentRepo
	users repo.UserRepo
}

func NewStudentSvc(r repo.StudentRepo, users repo.UserRepo) *StudentSvc {
	return &StudentSvc{repo: r, users: users}
}

// Create adds a new student under the client-supplied id. Only teachers/admins may create students.
func (s *StudentSvc) Create(accessToken string, id uint, name, profilePicURL string) ([]byte, int, error) {
	if status, err := requireTeacher(s.users, accessToken); err != nil {
		return nil, status, err
	}
	if err := s.repo.CreateStudent(id, name, profilePicURL); err != nil {
		if errors.Is(err, apperr.ErrStudentExists) {
			return nil, http.StatusConflict, err
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

func (s *StudentSvc) Update(accessToken string, id uint, name, profilePicURL string) ([]byte, int, error) {
	caller, status, err := getCaller(s.users, accessToken)
	if err != nil {
		return nil, status, err
	}
	if caller.Role < model.RoleTeacher && !slices.Contains(caller.Students, id) {
		return nil, http.StatusForbidden, fmt.Errorf("權限不足")
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

func (s *StudentSvc) SetStudents(accessToken string, userID uint, studentIDs []uint) ([]byte, int, error) {
	if status, err := requireTeacher(s.users, accessToken); err != nil {
		return nil, status, err
	}

	results := make([]model.StudentAssignResult, 0, len(studentIDs))
	seen := make(map[uint]struct{}, len(studentIDs))
	valid := make([]uint, 0, len(studentIDs))
	for _, id := range studentIDs {
		if _, dup := seen[id]; dup {
			continue
		}
		seen[id] = struct{}{}
		if _, err := s.repo.GetStudent(id); err != nil {
			if errors.Is(err, apperr.ErrStudentNotFound) {
				results = append(results, model.StudentAssignResult{StudentID: id, Status: http.StatusNotFound, Error: apperr.ErrStudentNotFound.Error()})
				continue
			}
			return nil, http.StatusInternalServerError, err
		}
		valid = append(valid, id)
		results = append(results, model.StudentAssignResult{StudentID: id, Status: http.StatusOK})
	}

	if err := s.users.SetUserStudents(userID, valid); err != nil {
		if errors.Is(err, apperr.ErrUserNotFound) {
			return nil, http.StatusNotFound, fmt.Errorf("使用者不存在: %d", userID)
		}
		return nil, http.StatusInternalServerError, err
	}

	data, err := json.Marshal(model.SetStudentsResponse{Results: results})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusMultiStatus, nil
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
