package service

import (
	crand "crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"gb-api/internal/config"
	apperr "gb-api/internal/error"
	"gb-api/internal/model"
	"gb-api/internal/repo"

	"github.com/golang-jwt/jwt/v5"
)

const (
	accessTokenTTL  = 15 * time.Minute
	refreshTokenTTL = 7 * 24 * time.Hour
)

type AuthSvc struct {
	users  repo.UserRepo
	tokens repo.RefreshTokenRepo
}

func NewAuthSvc(users repo.UserRepo, tokens repo.RefreshTokenRepo) *AuthSvc {
	return &AuthSvc{users: users, tokens: tokens}
}

func signToken(claims *model.Claims, key []byte) (string, error) {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(key)
}

// newJTI returns a random 128-bit token identifier as 32 hex chars.
func newJTI() (string, error) {
	b := make([]byte, 16)
	if _, err := crand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func (s *AuthSvc) newAccessToken(username string) (string, error) {
	t := time.Now()
	return signToken(&model.Claims{
		Username:  username,
		TokenType: "access",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(t.Add(accessTokenTTL)),
			IssuedAt:  jwt.NewNumericDate(t),
		},
	}, config.JwtKey)
}

// newRefreshToken mints a refresh token carrying a unique jti, which it also
// returns so the caller can register the jti as the single-use handle for this
// token in the store.
func (s *AuthSvc) newRefreshToken(username string) (token, jti string, err error) {
	jti, err = newJTI()
	if err != nil {
		return "", "", err
	}
	t := time.Now()
	token, err = signToken(&model.Claims{
		Username:  username,
		TokenType: "refresh",
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        jti,
			ExpiresAt: jwt.NewNumericDate(t.Add(refreshTokenTTL)),
			IssuedAt:  jwt.NewNumericDate(t),
		},
	}, config.RefreshKey)
	if err != nil {
		return "", "", err
	}
	return token, jti, nil
}

// genTokenPair returns a fresh access/refresh token pair plus the refresh
// token's jti (its key in the refresh-token store).
func (s *AuthSvc) genTokenPair(username string) (accessToken, refreshToken, jti string, err error) {
	accessToken, err = s.newAccessToken(username)
	if err != nil {
		return "", "", "", err
	}
	refreshToken, jti, err = s.newRefreshToken(username)
	if err != nil {
		return "", "", "", err
	}
	return accessToken, refreshToken, jti, nil
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
	ok, err := s.users.ValidateCredentials(creds.Username, creds.Password)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if !ok {
		return nil, http.StatusUnauthorized, fmt.Errorf("帳號或密碼錯誤")
	}

	accessToken, refreshToken, jti, err := s.genTokenPair(creds.Username)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	s.tokens.StoreRefreshToken(jti)

	data, err := marshalTokenPair(accessToken, refreshToken)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

// QueryUser lists all users. Any authenticated user may call it.
func (s *AuthSvc) QueryUser(accessToken string) ([]byte, int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return nil, http.StatusUnauthorized, err
	}
	users, err := s.users.GetAllUsers()
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	data, err := json.Marshal(model.UsersResponse{Users: users})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func (s *AuthSvc) RegisterUser(accessToken, username, password string, role uint) (int, error) {
	claims, err := validateAccessToken(accessToken)
	if err != nil {
		return http.StatusUnauthorized, err
	}
	callerRole, err := s.users.GetRole(claims.Username)
	if err != nil {
		return http.StatusInternalServerError, err
	}
	if callerRole < model.RoleTeacher {
		return http.StatusForbidden, fmt.Errorf("權限不足")
	}
	if role > model.RoleTeacher {
		return http.StatusForbidden, fmt.Errorf("無法建立此權限的使用者")
	}
	if err := s.users.CreateUser(username, password, role); err != nil {
		if errors.Is(err, apperr.ErrUserExists) {
			return http.StatusConflict, err
		}
		return http.StatusInternalServerError, err
	}
	return http.StatusCreated, nil
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

	ok, err := s.tokens.ConsumeRefreshToken(claims.ID)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if !ok {
		return nil, http.StatusUnauthorized, fmt.Errorf("refresh token invalid")
	}

	accessToken, newRefresh, jti, err := s.genTokenPair(claims.Username)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	s.tokens.StoreRefreshToken(jti)

	data, err := marshalTokenPair(accessToken, newRefresh)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}
