package service

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"

	configs "gb-api/internal/config"
	"gb-api/internal/model"

	"github.com/golang-jwt/jwt/v5"
)

var refreshTokens sync.Map // valid refresh token strings → struct{}{}

var now = time.Now // overridable in tests

const (
	accessTokenTTL  = 15 * time.Minute
	refreshTokenTTL = 7 * 24 * time.Hour
)

func signToken(claims *model.Claims, key []byte) (string, error) {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(key)
}

func newAccessToken(username string) (string, error) {
	t := now()
	return signToken(&model.Claims{
		Username:  username,
		TokenType: "access",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(t.Add(accessTokenTTL)),
			IssuedAt:  jwt.NewNumericDate(t),
		},
	}, configs.JwtKey)
}

func newRefreshToken(username string) (string, error) {
	t := now()
	return signToken(&model.Claims{
		Username:  username,
		TokenType: "refresh",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(t.Add(refreshTokenTTL)),
			IssuedAt:  jwt.NewNumericDate(t),
		},
	}, configs.RefreshKey)
}

func marshalTokenPair(accessToken, refreshToken string) ([]byte, error) {
	return json.Marshal(map[string]string{
		"access_token":  accessToken,
		"refresh_token": refreshToken,
	})
}

func LoginByName(creds model.Credential) ([]byte, int, error) {
	// TODO: replace with DB lookup when PostgreSQL is integrated
	if creds.Username != "user" || creds.Password != "password123" {
		return nil, http.StatusUnauthorized, fmt.Errorf("帳號或密碼錯誤")
	}

	accessToken, err := newAccessToken(creds.Username)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	refreshToken, err := newRefreshToken(creds.Username)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	refreshTokens.Store(refreshToken, struct{}{})

	data, err := marshalTokenPair(accessToken, refreshToken)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func RefreshTokens(refreshTokenStr string) ([]byte, int, error) {
	claims := &model.Claims{}
	token, err := jwt.ParseWithClaims(refreshTokenStr, claims, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("未預期的簽章演算法: %v", t.Header["alg"])
		}
		return configs.RefreshKey, nil
	})
	if err != nil || !token.Valid {
		return nil, http.StatusUnauthorized, fmt.Errorf("refresh token 無效或已過期")
	}
	if claims.TokenType != "refresh" {
		return nil, http.StatusUnauthorized, fmt.Errorf("token 類型錯誤")
	}

	if _, ok := refreshTokens.LoadAndDelete(refreshTokenStr); !ok {
		return nil, http.StatusUnauthorized, fmt.Errorf("refresh token invalid")
	}

	accessToken, err := newAccessToken(claims.Username)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	newRefresh, err := newRefreshToken(claims.Username)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	refreshTokens.Store(newRefresh, struct{}{})

	data, err := marshalTokenPair(accessToken, newRefresh)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func QueryDashboard(tokenString string) ([]byte, int, error) {
	claims := &model.Claims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("未預期的簽章演算法: %v", t.Header["alg"])
		}
		return configs.JwtKey, nil
	})
	if err != nil || !token.Valid {
		return nil, http.StatusUnauthorized, fmt.Errorf("token 無效或已過期")
	}
	if claims.TokenType != "access" {
		return nil, http.StatusUnauthorized, fmt.Errorf("請使用 access token")
	}

	data, err := json.Marshal(map[string]string{"message": "恭喜！您已成功通過 JWT 驗證，並讀取了受保護的資料庫內容。"})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}
