package service

import (
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
