package service

import (
	"fmt"
	"net/http"
	"time"

	"gb-api/internal/config"
	"gb-api/internal/model"

	"github.com/golang-jwt/jwt/v5"
)


func LoginByName(creds model.Credential) (error, int, string) {
	// 未來引入 PostgreSQL 後，這裡會改成：err := db.ValidateUser(creds.Username, creds.Password)
	if creds.Username != "user" || creds.Password != "password123" {
		return fmt.Errorf("帳號或密碼錯誤"), http.StatusUnauthorized, ""
	}

	// 設定 Token 的過期時間（例如：5 分鐘）
	expirationTime := time.Now().Add(5 * time.Minute)

	// 建立 JWT Claims
	claims := &model.Claims{
		Username: creds.Username,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expirationTime),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}

	// 使用 HS256 演算法簽章並產生 Token 字串
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString(configs.JwtKey)
	if err != nil {
		return err, http.StatusInternalServerError, ""
	}

	return nil, http.StatusOK, tokenString
}

// return string should be replace to model
func QueryDashboard(tokenString string, claims *model.Claims) (error, int, string) {
	// 解析並驗證 Token
	token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
		// 確保簽章演算法是預期的 HS256
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("未預期的簽章演算法: %v", token.Header["alg"])
		}
		return configs.JwtKey, nil
	})

	if err != nil {
		return err, http.StatusUnauthorized, ""
	}
	if !token.Valid {
		return fmt.Errorf("token invalid"), http.StatusUnauthorized, ""
	}

	return nil, http.StatusOK, "恭喜！您已成功通過 JWT 驗證，並讀取了受保護的資料庫內容。"
}
