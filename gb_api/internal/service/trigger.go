package service

import (
	"encoding/json"
	"errors"
	"fmt"
	mrand "math/rand"
	"net/http"
	"slices"
	"strings"
	"time"

	apperr "gb-api/internal/error"
	"gb-api/internal/model"
	"gb-api/internal/repo"
)

func marshalQuestionResponse(session string, content model.Content) ([]byte, int, error) {
	data, err := json.Marshal(model.QuestionResponse{Session: session, Content: content})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

type TriggerSvc struct {
	question  repo.QuestionRepo
	users     repo.UserRepo
	buildings repo.BuildingRepo
	items     repo.ItemRepo
	inv       repo.InventoryRepo
	blocks    repo.BlockRepo
	stt       repo.STTRepo
}

func NewTriggerSvc(r repo.QuestionRepo, users repo.UserRepo, buildings repo.BuildingRepo, items repo.ItemRepo, inv repo.InventoryRepo, blocks repo.BlockRepo, stt repo.STTRepo) *TriggerSvc {
	return &TriggerSvc{question: r, users: users, buildings: buildings, items: items, inv: inv, blocks: blocks, stt: stt}
}

// GenerateItem (QUIZ1 state) creates a new item of a random type for the requested difficulty
func (s *TriggerSvc) GenerateItem(accessToken string, difficulty uint) ([]byte, int, error) {
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

	qid, q, ok, err := s.question.RandomQuestion(1, &difficulty)
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
	id, err := s.question.StoreSession(model.QuestionSession{
		UserID:   caller.ID,
		Question: q,
		Kind:     model.KindItem,
		ItemID:   itemID,
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return marshalQuestionResponse(id, q.Content)
}

func (s *TriggerSvc) randomTypeForDifficulty(buildingID, difficulty uint) (uint, bool, error) {
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

func (s *TriggerSvc) itemIDQuestion(id uint) (*model.Question, int, error) {
	it, found, err := s.items.GetItem(id)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if !found || it.QuestionID == 0 {
		return nil, http.StatusBadRequest, fmt.Errorf("目標物品沒有題目")
	}
	gq, found, err := s.question.GetQuestion(it.QuestionID)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if !found {
		return nil, http.StatusBadRequest, fmt.Errorf("目標物品沒有題目")
	}
	return &gq, http.StatusOK, nil
}

func (s *TriggerSvc) GenerateTarget(accessToken string, targetUserID uint, targetSlotID uint) ([]byte, int, error) {
	caller, status, err := studentBlockedNotQuiz2(s.users, accessToken)
	if err != nil {
		return nil, status, err
	}

	// The target user must exist; an unknown target is a 404.
	if _, err := s.users.GetUserByID(targetUserID); err != nil {
		if errors.Is(err, apperr.ErrUserNotFound) {
			return nil, http.StatusNotFound, fmt.Errorf("使用者不存在")
		}
		return nil, http.StatusInternalServerError, err
	}
	slots, err := s.inv.QuerySlot(targetUserID)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	v, ok := slots[targetSlotID]
	if !ok || v == 0 {
		return nil, http.StatusBadRequest, fmt.Errorf("目標格子沒有物品")
	}
	// v is the signed slot value (negative = broken); the item id is its magnitude.
	itemID := v
	if itemID < 0 {
		itemID = -itemID
	}
	slotQ, status, err := s.itemIDQuestion(uint(itemID))
	if err != nil {
		return nil, status, err
	}

	attack := targetUserID != caller.ID && v > 0
	repair := targetUserID == caller.ID && v < 0
	if !attack && !repair {
		return nil, http.StatusBadRequest, fmt.Errorf("無效的目標")
	}

	// A failed attack bars the attacker from this slot until it is repaired.
	// TODO: teacher/admin bypass
	var q model.Question
	if attack {
		blocked, err := s.blocks.IsAttackBlocked(targetUserID, targetSlotID, caller.ID)
		if err != nil {
			return nil, http.StatusInternalServerError, err
		}
		if blocked {
			return nil, http.StatusForbidden, fmt.Errorf("攻擊失敗後需等待此格子修復才能再次攻擊")
		}
		q = *slotQ
	} else {
		_, gq, found, err := s.question.RandomQuestion(2, &slotQ.Difficulty)
		if err != nil {
			return nil, http.StatusInternalServerError, err
		}
		if !found {
			return nil, http.StatusBadRequest, fmt.Errorf("area 2 沒有題目")
		}
		q = gq
	}

	id, err := s.question.StoreSession(model.QuestionSession{
		UserID:   caller.ID,
		Question: q,
		Kind:     model.KindTarget,
		Target:   &model.Target{UserID: targetUserID, SlotID: targetSlotID},
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return marshalQuestionResponse(id, q.Content)
}

func (s *TriggerSvc) Answer(accessToken, session string, raw json.RawMessage) ([]byte, int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return nil, http.StatusUnauthorized, err
	}
	qs, ok, err := s.question.ConsumeSession(session)
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
			if err := s.inv.AddInvItem(qs.UserID, qs.ItemID); err != nil {
				return nil, http.StatusInternalServerError, err
			}
			resp.ItemID = qs.ItemID
		}
	case model.KindTarget:
		if qs.Target != nil {
			if correct {
				success, err := s.applyTarget(qs.UserID, *qs.Target)
				if err != nil {
					return nil, http.StatusInternalServerError, err
				}
				resp.Success = &success
			} else if qs.Target.UserID != qs.UserID {
				// A failed attack (not a repair) bars this attacker from the slot
				// until it is repaired.
				if err := s.blocks.AddAttackBlock(qs.Target.UserID, qs.Target.SlotID, qs.UserID); err != nil {
					return nil, http.StatusInternalServerError, err
				}
			}
		}
	}

	data, err := json.Marshal(resp)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func (s *TriggerSvc) applyTarget(callerID uint, t model.Target) (bool, error) {
	slots, err := s.inv.QuerySlot(t.UserID)
	if err != nil {
		return false, err
	}
	v, ok := slots[t.SlotID]
	if !ok || v == 0 {
		return false, nil
	}
	attack := t.UserID != callerID
	if attack && v < 0 { // already broken
		return false, nil
	}
	if !attack && v > 0 { // not broken, nothing to repair
		return false, nil
	}
	if err := s.inv.SetSlot(t.UserID, t.SlotID, -v); err != nil {
		return false, err
	}
	if !attack {
		// Repair lifts every attacker block on this slot.
		if err := s.blocks.ClearAttackBlocks(t.UserID, t.SlotID); err != nil {
			return false, err
		}
	}
	broadcastSlotUpdate(t.UserID)
	return true, nil
}

// grade evaluates a submitted answer against the question's stored answer.
func (s *TriggerSvc) grade(answer model.Answer, raw json.RawMessage) (bool, int, error) {
	switch answer.Type {
	case model.AnswerIndex:
		var want []uint
		if err := json.Unmarshal(answer.Data, &want); err != nil {
			return false, http.StatusInternalServerError, fmt.Errorf("題目答案格式錯誤")
		}
		var got uint
		if err := json.Unmarshal(raw, &got); err != nil {
			return false, http.StatusBadRequest, fmt.Errorf("不合法的 answer")
		}
		return slices.Contains(want, got), http.StatusOK, nil
	case model.AnswerVoice:
		var want []string
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
		got := strings.TrimSpace(transcript)
		for _, w := range want {
			if strings.EqualFold(got, strings.TrimSpace(w)) {
				return true, http.StatusOK, nil
			}
		}
		return false, http.StatusOK, nil
	default:
		return false, http.StatusInternalServerError, fmt.Errorf("未知的答案類型")
	}
}
