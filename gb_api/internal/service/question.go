package service

import (
	"encoding/json"
	"fmt"
	"net/http"

	"gb-api/internal/model"
	"gb-api/internal/repo"
)

type QuestionSvc struct {
	repo  repo.QuestionRepo
	users repo.UserRepo
}

func NewQuestionSvc(r repo.QuestionRepo, users repo.UserRepo) *QuestionSvc {
	return &QuestionSvc{repo: r, users: users}
}

func (s *QuestionSvc) Upload(accessToken string, inputs []model.QuestionInput) ([]byte, int, error) {
	if status, err := requireTeacher(s.users, accessToken); err != nil {
		return nil, status, err
	}
	if len(inputs) == 0 {
		return nil, http.StatusBadRequest, fmt.Errorf("缺少 questions")
	}

	results := make([]model.QuestionUploadResult, len(inputs))
	valid := make([]model.Question, 0, len(inputs))
	validIdx := make([]int, 0, len(inputs))
	for i, in := range inputs {
		if err := validateQuestionInput(in); err != nil {
			results[i] = model.QuestionUploadResult{
				Index:  i,
				Status: http.StatusBadRequest,
				Error:  err.Error(),
			}
			continue
		}
		valid = append(valid, model.Question{Content: in.Content, Answer: in.Answer, Difficulty: in.Difficulty, Area: in.Area})
		validIdx = append(validIdx, i)
	}

	if len(valid) > 0 {
		records, err := s.repo.AddQuestions(valid)
		if err != nil {
			return nil, http.StatusInternalServerError, err
		}
		for j, rec := range records {
			results[validIdx[j]] = model.QuestionUploadResult{
				Index:  validIdx[j],
				Status: http.StatusCreated,
				ID:     rec.ID,
			}
		}
	}

	data, err := json.Marshal(model.UploadQuestionsResponse{Results: results})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusMultiStatus, nil
}

func (s *QuestionSvc) Search(accessToken string, difficulty, area *uint) ([]byte, int, error) {
	if status, err := requireTeacher(s.users, accessToken); err != nil {
		return nil, status, err
	}
	records, err := s.repo.SearchQuestions(difficulty, area)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(model.QuestionListResponse{Questions: records})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

// Get returns a single pooled question by id. Any authenticated user may call it; the
// full record (including the answer) is returned.
func (s *QuestionSvc) Get(accessToken string, id uint) ([]byte, int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return nil, http.StatusUnauthorized, err
	}
	q, ok, err := s.repo.GetQuestion(id)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if !ok {
		return nil, http.StatusNotFound, fmt.Errorf("question 不存在")
	}
	data, err := json.Marshal(model.QuestionRecord{
		ID: id, Content: q.Content, Answer: q.Answer, Difficulty: q.Difficulty, Area: q.Area,
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func (s *QuestionSvc) Update(accessToken string, id uint, in model.QuestionInput) (int, error) {
	if status, err := requireTeacher(s.users, accessToken); err != nil {
		return status, err
	}
	if err := validateQuestionInput(in); err != nil {
		return http.StatusBadRequest, err
	}
	ok, err := s.repo.UpdateQuestion(id, model.Question{Content: in.Content, Answer: in.Answer, Difficulty: in.Difficulty, Area: in.Area})
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if !ok {
		return http.StatusNotFound, fmt.Errorf("question 不存在")
	}
	return http.StatusOK, nil
}

func (s *QuestionSvc) Delete(accessToken string, id uint) (int, error) {
	if status, err := requireTeacher(s.users, accessToken); err != nil {
		return status, err
	}
	ok, err := s.repo.DeleteQuestion(id)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if !ok {
		return http.StatusNotFound, fmt.Errorf("question 不存在")
	}
	return http.StatusOK, nil
}
