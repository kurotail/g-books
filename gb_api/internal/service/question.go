package service

import (
	"encoding/json"
	"errors"
	"fmt"
	mrand "math/rand"
	"net/http"
	"time"

	apperr "gb-api/internal/error"
	"gb-api/internal/model"
	"gb-api/internal/repo"
)

type QuestionSvc struct {
	repo      repo.QuestionRepo
	users     repo.UserRepo
	groups    repo.GroupRepo
	buildings repo.BuildingRepo
	items     repo.ItemRepo
}

func NewQuestionSvc(r repo.QuestionRepo, users repo.UserRepo, groups repo.GroupRepo, buildings repo.BuildingRepo, items repo.ItemRepo) *QuestionSvc {
	return &QuestionSvc{repo: r, users: users, groups: groups, buildings: buildings, items: items}
}

// GenerateItem (NORMAL state) creates a new item of a random type for the requested
// difficulty — drawn from the caller-group's building DifficultyType — tied to a random
// area-1 question of that difficulty. Answering correctly grants the item.
func (s *QuestionSvc) GenerateItem(accessToken string, difficulty uint) ([]byte, int, error) {
	caller, status, err := studentBlockedNotNormal(s.users, accessToken)
	if err != nil {
		return nil, status, err
	}
	if caller.GroupID == 0 {
		return nil, http.StatusBadRequest, fmt.Errorf("尚未加入任何群組")
	}

	g, err := s.groups.GetGroup(caller.GroupID)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	itemType, ok, err := s.randomTypeForDifficulty(g.BuildingID, difficulty)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if !ok {
		return nil, http.StatusBadRequest, fmt.Errorf("該難度沒有可用的物品類型")
	}

	qid, q, ok, err := s.repo.RandomQuestion(1, &difficulty)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if !ok {
		return nil, http.StatusBadRequest, fmt.Errorf("難度 %d 在 area 1 沒有題目", difficulty)
	}

	itemID, err := s.items.CreateItem(itemType, qid)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	id, err := s.repo.StoreSession(model.QuestionSession{
		GroupID:  caller.GroupID,
		Question: q,
		Kind:     model.KindItem,
		ItemID:   itemID,
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return marshalQuestionResponse(id, q.Description)
}

func (s *QuestionSvc) randomTypeForDifficulty(buildingID, difficulty uint) (uint, bool, error) {
	if buildingID == 0 {
		return 0, false, nil
	}
	b, err := s.buildings.GetBuilding(buildingID)
	if err != nil {
		if errors.Is(err, apperr.ErrBuildingNotFound) {
			return 0, false, nil
		}
		return 0, false, err
	}
	types := b.DifficultyType[difficulty]
	if len(types) == 0 {
		return 0, false, nil
	}
	return types[mrand.Intn(len(types))], true, nil
}

func (s *QuestionSvc) GenerateTarget(accessToken string, targetGroupID, targetSlotID uint) ([]byte, int, error) {
	caller, status, err := studentBlockedNotQuiz2(s.users, accessToken)
	if err != nil {
		return nil, status, err
	}
	if caller.GroupID == 0 {
		return nil, http.StatusBadRequest, fmt.Errorf("尚未加入任何群組")
	}

	slots, err := s.items.QuerySlot(targetGroupID)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	v, ok := slots[targetSlotID]
	if !ok || v == 0 {
		return nil, http.StatusBadRequest, fmt.Errorf("目標格子沒有物品")
	}

	attack := targetGroupID != caller.GroupID && v > 0
	repair := targetGroupID == caller.GroupID && v < 0
	if !attack && !repair {
		return nil, http.StatusBadRequest, fmt.Errorf("無效的目標")
	}

	var q model.Question
	if attack {
		it, found, err := s.items.GetItem(uint(v))
		if err != nil {
			return nil, http.StatusInternalServerError, err
		}
		if !found || it.QuestionID == 0 {
			return nil, http.StatusBadRequest, fmt.Errorf("目標物品沒有題目")
		}
		gq, found, err := s.repo.GetQuestion(it.QuestionID)
		if err != nil {
			return nil, http.StatusInternalServerError, err
		}
		if !found {
			return nil, http.StatusBadRequest, fmt.Errorf("目標物品沒有題目")
		}
		q = gq
	} else {
		_, gq, found, err := s.repo.RandomQuestion(2, nil)
		if err != nil {
			return nil, http.StatusInternalServerError, err
		}
		if !found {
			return nil, http.StatusBadRequest, fmt.Errorf("area 2 沒有題目")
		}
		q = gq
	}

	id, err := s.repo.StoreSession(model.QuestionSession{
		GroupID:  caller.GroupID,
		Question: q,
		Kind:     model.KindTarget,
		Target:   &model.Target{GroupID: targetGroupID, SlotID: targetSlotID},
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return marshalQuestionResponse(id, q.Description)
}

func marshalQuestionResponse(session, description string) ([]byte, int, error) {
	data, err := json.Marshal(model.QuestionResponse{Session: session, Description: description})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
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
	if status, err := requireTeacher(s.users, accessToken); err != nil {
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
	if status, err := requireTeacher(s.users, accessToken); err != nil {
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

func (s *QuestionSvc) Answer(accessToken, session string, ans uint) ([]byte, int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return nil, http.StatusUnauthorized, err
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

	correct := ans == qs.Answer
	resp := model.AnswerResponse{Correct: correct}

	switch qs.Kind {
	case model.KindItem:
		if correct {
			if err := s.items.AddInvItem(qs.GroupID, qs.ItemID); err != nil {
				return nil, http.StatusInternalServerError, err
			}
			resp.ItemID = qs.ItemID
		}
	case model.KindTarget:
		if correct && qs.Target != nil {
			success, err := s.applyTarget(qs.GroupID, *qs.Target)
			if err != nil {
				return nil, http.StatusInternalServerError, err
			}
			resp.Success = &success
		}
	}

	data, err := json.Marshal(resp)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func (s *QuestionSvc) applyTarget(callerGroupID uint, t model.Target) (bool, error) {
	slots, err := s.items.QuerySlot(t.GroupID)
	if err != nil {
		return false, err
	}
	v, ok := slots[t.SlotID]
	if !ok || v == 0 {
		return false, nil
	}
	attack := t.GroupID != callerGroupID
	if attack && v < 0 { // already broken
		return false, nil
	}
	if !attack && v > 0 { // not broken, nothing to repair
		return false, nil
	}
	if err := s.items.SetSlot(t.GroupID, t.SlotID, -v); err != nil {
		return false, err
	}
	return true, nil
}
