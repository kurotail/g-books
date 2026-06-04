package handler

import (
	"encoding/json"
	"net/http"

	"gb-api/internal/model"
	"gb-api/internal/service"
)

type AuthHandler struct {
	svc *service.AuthSvc
}

func NewAuthHandler(s *service.AuthSvc) *AuthHandler{
	return &AuthHandler{svc: s}
}

func writeJSON(w http.ResponseWriter, data []byte) {
	w.Header().Set("Content-Type", "application/json")
	w.Write(data)
}

func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "只接受 POST 請求", http.StatusMethodNotAllowed)
		return
	}

	var creds model.Credential
	if err := json.NewDecoder(r.Body).Decode(&creds); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}

	data, status, err := h.svc.LoginByName(creds)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

func (h *AuthHandler) QueryUser(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	data, status, err := h.svc.QueryUser(token)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

func (h *AuthHandler) Refresh(w http.ResponseWriter, r *http.Request) {
	var req model.RefreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.RefreshToken == "" {
		http.Error(w, "缺少或不合法的 refresh_token", http.StatusBadRequest)
		return
	}

	data, status, err := h.svc.RefreshTokens(req.RefreshToken)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}
