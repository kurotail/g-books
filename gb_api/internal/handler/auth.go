package handler

import (
	"encoding/json"
	"net/http"
	"strings"

	"gb-api/internal/model"
	"gb-api/internal/service"
)

// 2. 登入處理函式（第一階段：寫死使用者資訊）
func LoginHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "只接受 POST 請求", http.StatusMethodNotAllowed)
		return
	}

	var creds model.Credential
	err := json.NewDecoder(r.Body).Decode(&creds)
	if err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}

	err, status, outString := service.LoginByName(creds)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}

	// 回傳 Token 給前端（Flutter 等）
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"token": outString,
	})
}

// 3. JWT 驗證中間件（Middleware）
func QueryHandler(w http.ResponseWriter, r *http.Request) {

	// 從 Header 讀取 Authorization: Bearer <Token>
	authHeader := r.Header.Get("Authorization")
	if authHeader == "" {
		http.Error(w, "未附帶授權令牌 (Missing Token)", http.StatusUnauthorized)
		return
	}

	parts := strings.Split(authHeader, " ")
	if len(parts) != 2 || parts[0] != "Bearer" {
		http.Error(w, "Authorization Header 格式必須為 Bearer <Token>", http.StatusUnauthorized)
		return
	}

	tokenString := parts[1]
	claims := &model.Claims{}

	err, status, outString := service.QueryDashboard(tokenString, claims)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"message": outString,
	})
}
