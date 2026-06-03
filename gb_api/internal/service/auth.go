package service

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"gb-api/internal/config"
	"gb-api/internal/model"
	"gb-api/internal/repo"

	"github.com/golang-jwt/jwt/v5"
)

const (
	accessTokenTTL  = 15 * time.Minute
	refreshTokenTTL = 7 * 24 * time.Hour
)

var now = time.Now
type AuthSvc struct {
	repo repo.AuthRepo
}

func NewAuthSvc(r repo.AuthRepo) *AuthSvc {
	return &AuthSvc{repo: r}
}

func signToken(claims *model.Claims, key []byte) (string, error) {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(key)
}

func (s *AuthSvc) newAccessToken(username string) (string, error) {
	t := now()
	return signToken(&model.Claims{
		Username:  username,
		TokenType: "access",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(t.Add(accessTokenTTL)),
			IssuedAt:  jwt.NewNumericDate(t),
		},
	}, config.JwtKey)
}

func (s *AuthSvc) newRefreshToken(username string) (string, error) {
	t := now()
	return signToken(&model.Claims{
		Username:  username,
		TokenType: "refresh",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(t.Add(refreshTokenTTL)),
			IssuedAt:  jwt.NewNumericDate(t),
		},
	}, config.RefreshKey)
}

func (s *AuthSvc) genTokenPair(username string) (string, string, error) {
	accessToken, err := s.newAccessToken(username)
	if err != nil {
		return "", "", err
	}
	refreshToken, err := s.newRefreshToken(username)
	if err != nil {
		return "", "", err
	}
	return accessToken, refreshToken, nil
}

func marshalTokenPair(accessToken, refreshToken string) ([]byte, error) {
	return json.Marshal(map[string]string{
		"access_token":  accessToken,
		"refresh_token": refreshToken,
	})
}

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

func (s *AuthSvc) LoginByName(creds model.Credential) ([]byte, int, error) {
	ok, err := s.repo.ValidateCredentials(creds.Username, creds.Password)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if !ok {
		return nil, http.StatusUnauthorized, fmt.Errorf("帳號或密碼錯誤")
	}

	accessToken, refreshToken, err := s.genTokenPair(creds.Username)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	s.repo.StoreRefreshToken(refreshToken)

	data, err := marshalTokenPair(accessToken, refreshToken)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func (s *AuthSvc) RefreshTokens(refreshTokenStr string) ([]byte, int, error) {
	claims := &model.Claims{}
	token, err := jwt.ParseWithClaims(refreshTokenStr, claims, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("未預期的簽章演算法: %v", t.Header["alg"])
		}
		return config.RefreshKey, nil
	})
	if err != nil || !token.Valid {
		return nil, http.StatusUnauthorized, fmt.Errorf("refresh token 無效或已過期")
	}
	if claims.TokenType != "refresh" {
		return nil, http.StatusUnauthorized, fmt.Errorf("token 類型錯誤")
	}

	ok, err := s.repo.ConsumeRefreshToken(refreshTokenStr)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if !ok {
		return nil, http.StatusUnauthorized, fmt.Errorf("refresh token invalid")
	}

	accessToken, newRefresh, err := s.genTokenPair(claims.Username)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	s.repo.StoreRefreshToken(newRefresh)

	data, err := marshalTokenPair(accessToken, newRefresh)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func QueryDashboard(tokenString string) ([]byte, int, error) {
	if _, err := validateAccessToken(tokenString); err != nil {
		return nil, http.StatusUnauthorized, err
	}

	data, err := json.Marshal(map[string]string{"message": "恭喜！您已成功通過 JWT 驗證，並讀取了受保護的資料庫內容。"})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}
