package service

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"

	"gb-api/internal/config"
	apperr "gb-api/internal/error"
	"gb-api/internal/model"
	"gb-api/internal/repo"

	"github.com/golang-jwt/jwt/v5"
)

func validateAccessToken(tokenString string) (*model.Claims, error) {
	claims := &model.Claims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("未預期的簽章演算法: %v", t.Header["alg"])
		}
		return config.JwtKey, nil
	})
	if err != nil || !token.Valid {
		return nil, fmt.Errorf("token 無效或已過期")
	}
	if claims.TokenType != "access" {
		return nil, fmt.Errorf("請使用 access token")
	}
	return claims, nil
}

func getCaller(r repo.UserRepo, accessToken string) (*model.User, int, error) {
	claims, err := validateAccessToken(accessToken)
	if err != nil {
		return nil, http.StatusUnauthorized, err
	}
	caller, err := r.GetUserByID(claims.UserID)
	if err != nil {
		if errors.Is(err, apperr.ErrUserNotFound) {
			return nil, http.StatusUnauthorized, fmt.Errorf("使用者不存在")
		}
		return nil, http.StatusInternalServerError, err
	}
	return &caller, http.StatusOK, nil
}

func requireTeacher(r repo.UserRepo, accessToken string) (int, error) {
	caller, status, err := getCaller(r, accessToken)
	if err != nil {
		return status, err
	}
	if caller.Role < model.RoleTeacher {
		return http.StatusForbidden, fmt.Errorf("權限不足")
	}
	return http.StatusOK, nil
}

func studentBlockedNotQuiz2(r repo.UserRepo, accessToken string) (*model.User, int, error) {
	caller, status, err := getCaller(r, accessToken)
	if err != nil {
		return nil, status, err
	}
	if caller.Role <= model.RoleStudent && getState() != model.StateQuiz2 {
		return nil, http.StatusForbidden, fmt.Errorf("權限不足")
	}
	return caller, http.StatusOK, nil
}

func studentBlockedNotQuiz1(r repo.UserRepo, accessToken string) (*model.User, int, error) {
	caller, status, err := getCaller(r, accessToken)
	if err != nil {
		return nil, status, err
	}
	if caller.Role <= model.RoleStudent && getState() != model.StateQuiz1 {
		return nil, http.StatusForbidden, fmt.Errorf("權限不足")
	}
	return caller, http.StatusOK, nil
}

func (s *ItemSvc) blockStudentQuiz2(r repo.UserRepo, accessToken string) (*model.User, int, error) {
	caller, status, err := getCaller(r, accessToken)
	if err != nil {
		return nil, status, err
	}
	if caller.Role <= model.RoleStudent && getState() == model.StateQuiz2 {
		return nil, http.StatusForbidden, fmt.Errorf("QUIZ 狀態下學生無法移動物品")
	}
	return caller, http.StatusOK, nil
}

// allowed type-value sets for question validation.
var (
	descTypes    = map[string]struct{}{model.DescText: {}, model.DescAudio: {}, model.DescVoice: {}}
	choicesTypes = map[string]struct{}{model.ChoicesText: {}, model.ChoicesAudio: {}}
	answerTypes  = map[string]struct{}{model.AnswerIndex: {}, model.AnswerVoice: {}}
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
	if in.Content.Choices != nil {
		if _, ok := choicesTypes[in.Content.Choices.Type]; !ok {
			return fmt.Errorf("不合法的 choices type")
		}
	}
	if _, ok := answerTypes[in.Answer.Type]; !ok {
		return fmt.Errorf("不合法的 answer type")
	}
	if err := validateAnswerSet(in.Answer); err != nil {
		return err
	}
	return nil
}

// validateAnswerSet enforces that the answer carries a non-empty JSON array of the
// element type its answer type implies: indexes for AnswerIndex, transcripts for
// AnswerVoice. This rejects both the legacy scalar shape and an empty set.
func validateAnswerSet(answer model.Answer) error {
	switch answer.Type {
	case model.AnswerIndex:
		var set []uint
		if err := json.Unmarshal(answer.Data, &set); err != nil || len(set) == 0 {
			return fmt.Errorf("answer 必須為非空的索引陣列")
		}
	case model.AnswerVoice:
		var set []string
		if err := json.Unmarshal(answer.Data, &set); err != nil || len(set) == 0 {
			return fmt.Errorf("answer 必須為非空的字串陣列")
		}
	}
	return nil
}
