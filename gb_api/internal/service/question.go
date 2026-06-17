package service

import (
	"encoding/json"
	"errors"
	"fmt"
	mrand "math/rand"
	"net/http"
	"strings"
	"time"

	apperr "gb-api/internal/error"
	"gb-api/internal/model"
	"gb-api/internal/repo"
)

type QuestionSvc struct {
	repo      repo.QuestionRepo
	users     repo.UserRepo
	buildings repo.BuildingRepo
	items     repo.ItemRepo
	stt       repo.STTRepo
}

func NewQuestionSvc(r repo.QuestionRepo, users repo.UserRepo, buildings repo.BuildingRepo, items repo.ItemRepo, stt repo.STTRepo) *QuestionSvc {
	return &QuestionSvc{repo: r, users: users, buildings: buildings, items: items, stt: stt}
}

// GenerateItem (QUIZ1 state) creates a new item of a random type for the requested difficulty
func (s *QuestionSvc) GenerateItem(accessToken string, difficulty uint) ([]byte, int, error) {
	caller, status, err := studentBlockedNotQuiz1(s.users, accessToken)
	if err != nil {
		return nil, status, err
	}
	if caller.BuildingID == 0 {
		return nil, http.StatusBadRequest, fmt.Errorf("尚未指定建築")
	}

	itemType, ok, err := s.randomTypeForDifficulty(caller.BuildingID, difficulty)
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
		Username: caller.Username,
		Question: q,
		Kind:     model.KindItem,
		ItemID:   itemID,
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return marshalQuestionResponse(id, q.Content)
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

func (s *QuestionSvc) GenerateTarget(accessToken string, targetUsername string, targetSlotID uint) ([]byte, int, error) {
	caller, status, err := studentBlockedNotQuiz2(s.users, accessToken)
	if err != nil {
		return nil, status, err
	}

	slots, err := s.items.QuerySlot(targetUsername)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	v, ok := slots[targetSlotID]
	if !ok || v == 0 {
		return nil, http.StatusBadRequest, fmt.Errorf("目標格子沒有物品")
	}

	attack := targetUsername != caller.Username && v > 0
	repair := targetUsername == caller.Username && v < 0
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
		Username: caller.Username,
		Question: q,
		Kind:     model.KindTarget,
		Target:   &model.Target{Username: targetUsername, SlotID: targetSlotID},
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return marshalQuestionResponse(id, q.Content)
}

func marshalQuestionResponse(session string, content model.Content) ([]byte, int, error) {
	data, err := json.Marshal(model.QuestionResponse{Session: session, Content: content})
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

func (s *QuestionSvc) Answer(accessToken, session string, raw json.RawMessage) ([]byte, int, error) {
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

	correct, status, err := s.grade(qs.Answer, raw)
	if err != nil {
		return nil, status, err
	}
	resp := model.AnswerResponse{Correct: correct}

	switch qs.Kind {
	case model.KindItem:
		if correct {
			if err := s.items.AddInvItem(qs.Username, qs.ItemID); err != nil {
				return nil, http.StatusInternalServerError, err
			}
			resp.ItemID = qs.ItemID
		}
	case model.KindTarget:
		if correct && qs.Target != nil {
			success, err := s.applyTarget(qs.Username, *qs.Target)
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

func (s *QuestionSvc) applyTarget(callerUsername string, t model.Target) (bool, error) {
	slots, err := s.items.QuerySlot(t.Username)
	if err != nil {
		return false, err
	}
	v, ok := slots[t.SlotID]
	if !ok || v == 0 {
		return false, nil
	}
	attack := t.Username != callerUsername
	if attack && v < 0 { // already broken
		return false, nil
	}
	if !attack && v > 0 { // not broken, nothing to repair
		return false, nil
	}
	if err := s.items.SetSlot(t.Username, t.SlotID, -v); err != nil {
		return false, err
	}
	return true, nil
}

// grade evaluates a submitted answer against the question's stored answer.
func (s *QuestionSvc) grade(answer model.Answer, raw json.RawMessage) (bool, int, error) {
	switch answer.Type {
	case model.AnswerIndex:
		var want uint
		if err := json.Unmarshal(answer.Data, &want); err != nil {
			return false, http.StatusInternalServerError, fmt.Errorf("題目答案格式錯誤")
		}
		var got uint
		if err := json.Unmarshal(raw, &got); err != nil {
			return false, http.StatusBadRequest, fmt.Errorf("不合法的 answer")
		}
		return got == want, http.StatusOK, nil
	case model.AnswerVoice:
		var want string
		if err := json.Unmarshal(answer.Data, &want); err != nil {
			return false, http.StatusInternalServerError, fmt.Errorf("題目答案格式錯誤")
		}
		var b64 string
		if err := json.Unmarshal(raw, &b64); err != nil {
			return false, http.StatusBadRequest, fmt.Errorf("不合法的 answer")
		}
		transcript, err := s.stt.Transcribe(b64)
		if err != nil {
			return false, http.StatusInternalServerError, err
		}
		return strings.EqualFold(strings.TrimSpace(transcript), strings.TrimSpace(want)), http.StatusOK, nil
	default:
		return false, http.StatusInternalServerError, fmt.Errorf("未知的答案類型")
	}
}

// allowed type-value sets for question validation.
var (
	descTypes   = map[string]struct{}{model.DescText: {}, model.DescAudio: {}, model.DescVoice: {}}
	answerTypes = map[string]struct{}{model.AnswerIndex: {}, model.AnswerVoice: {}}
)

// validateQuestionInput enforces that the content/answer carry only known type values
// and a non-empty description. It does not check choice counts or index bounds.
func validateQuestionInput(in model.QuestionInput) error {
	if _, ok := descTypes[in.Content.Description.Type]; !ok {
		return fmt.Errorf("不合法的 description type")
	}
	if in.Content.Description.Data == "" {
		return fmt.Errorf("description 不可為空")
	}
	if in.Content.Choices != nil && in.Content.Choices.Type != model.ChoicesText {
		return fmt.Errorf("不合法的 choices type")
	}
	if _, ok := answerTypes[in.Answer.Type]; !ok {
		return fmt.Errorf("不合法的 answer type")
	}
	return nil
}
