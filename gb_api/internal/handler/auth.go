package handler

import (
	"encoding/json"
	"net/http"
	"strings"

	"gb-api/internal/model"
	"gb-api/internal/service"
)

func write_json_rsp(w http.ResponseWriter, data []byte) {
	w.Header().Set("Content-Type", "application/json")
	w.Write(data)
}

func LoginHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "只接受 POST 請求", http.StatusMethodNotAllowed)
		return
	}

	var creds model.Credential
	if err := json.NewDecoder(r.Body).Decode(&creds); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}

	data, status, err := service.LoginByName(creds)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	write_json_rsp(w, data)
}

func RefreshHandler(w http.ResponseWriter, r *http.Request) {
	var req model.RefreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.RefreshToken == "" {
		http.Error(w, "缺少或不合法的 refresh_token", http.StatusBadRequest)
		return
	}

	data, status, err := service.RefreshTokens(req.RefreshToken)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	write_json_rsp(w, data)
}

func QueryHandler(w http.ResponseWriter, r *http.Request) {
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

	data, status, err := service.QueryDashboard(parts[1])
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	write_json_rsp(w, data)
}
