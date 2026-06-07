package service

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

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

func (s *QuestionSvc) Generate(accessToken string, groupID uint) ([]byte, int, error) {
	claims, err := validateAccessToken(accessToken)
	if err != nil {
		return nil, http.StatusUnauthorized, err
	}
	caller, err := s.users.GetUser(claims.Username)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	// Teachers and admins may always generate; students only while the server
	// is in QUIZ state.
	if studentBlockedByState(caller.Role) {
		return nil, http.StatusForbidden, fmt.Errorf("NORMAL 狀態下學生無法產生題目")
	}
	id, q, err := s.repo.CreateSession(groupID)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(model.QuestionResponse{Session: id, Description: q.Description})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func (s *QuestionSvc) requireTeacher(accessToken string) (int, error) {
	claims, err := validateAccessToken(accessToken)
	if err != nil {
		return http.StatusUnauthorized, err
	}
	caller, err := s.users.GetUser(claims.Username)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if caller.Role < model.RoleTeacher {
		return http.StatusForbidden, fmt.Errorf("權限不足")
	}
	return http.StatusOK, nil
}

func (s *QuestionSvc) Upload(accessToken string, inputs []model.QuestionInput) ([]byte, int, error) {
	if status, err := s.requireTeacher(accessToken); err != nil {
		return nil, status, err
	}
	if len(inputs) == 0 {
		return nil, http.StatusBadRequest, fmt.Errorf("缺少 questions")
	}

	results := make([]model.QuestionUploadResult, len(inputs))
	valid := make([]model.Question, 0, len(inputs))
	validIdx := make([]int, 0, len(inputs))
	for i, in := range inputs {
		if in.Description == "" {
			results[i] = model.QuestionUploadResult{
				Index:  i,
				Status: http.StatusBadRequest,
				Error:  "description 不可為空",
			}
			continue
		}
		valid = append(valid, model.Question{Description: in.Description, Answer: in.Answer, Difficulty: in.Difficulty, Area: in.Area})
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

func (s *QuestionSvc) Search(accessToken, query string, difficulty, area *uint) ([]byte, int, error) {
	if status, err := s.requireTeacher(accessToken); err != nil {
		return nil, status, err
	}
	records, err := s.repo.SearchQuestions(query, difficulty, area)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(model.QuestionListResponse{Questions: records})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func (s *QuestionSvc) Update(accessToken string, id uint, in model.QuestionInput) (int, error) {
	if status, err := s.requireTeacher(accessToken); err != nil {
		return status, err
	}
	if in.Description == "" {
		return http.StatusBadRequest, fmt.Errorf("description 不可為空")
	}
	ok, err := s.repo.UpdateQuestion(id, model.Question{Description: in.Description, Answer: in.Answer, Difficulty: in.Difficulty, Area: in.Area})
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if !ok {
		return http.StatusNotFound, fmt.Errorf("question 不存在")
	}
	return http.StatusOK, nil
}

func (s *QuestionSvc) Delete(accessToken string, id uint) (int, error) {
	if status, err := s.requireTeacher(accessToken); err != nil {
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

func (s *QuestionSvc) Answer(accessToken, session string, ans uint) ([]byte, int, error) {
	claims, err := validateAccessToken(accessToken)
	if err != nil {
		return nil, http.StatusUnauthorized, err
	}
	caller, err := s.users.GetUser(claims.Username)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if studentBlockedByState(caller.Role) {
		return nil, http.StatusForbidden, fmt.Errorf("NORMAL 狀態下學生無法作答")
	}
	qs, ok, err := s.repo.ConsumeSession(session)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if !ok {
		return nil, http.StatusBadRequest, fmt.Errorf("session 不存在或已使用")
	}
	if time.Now().After(qs.ExpiresAt) {
		return nil, http.StatusBadRequest, fmt.Errorf("session 已過期")
	}
	data, err := json.Marshal(model.AnswerResponse{Correct: ans == qs.Answer})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}
