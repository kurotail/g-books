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

func NewAuthHandler(s *service.AuthSvc) *AuthHandler {
	return &AuthHandler{svc: s}
}

func writeJSON(w http.ResponseWriter, data []byte) {
	w.Header().Set("Content-Type", "application/json")
	w.Write(data)
}

func writeJSONStatus(w http.ResponseWriter, status int, data []byte) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
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
	if creds.Username == "" || creds.Password == "" {
		http.Error(w, "缺少 username 或 password", http.StatusBadRequest)
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

func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.RegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	if req.Username == "" || req.Password == "" {
		http.Error(w, "缺少 username 或 password", http.StatusBadRequest)
		return
	}
	if req.Role == nil {
		http.Error(w, "缺少 role", http.StatusBadRequest)
		return
	}
	if *req.Role > model.RoleAdmin {
		http.Error(w, "不合法的 role", http.StatusBadRequest)
		return
	}
	status, err := h.svc.RegisterUser(token, req.Username, req.Password, *req.Role, req.GroupID)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	w.WriteHeader(status)
}

func (h *AuthHandler) SetProfilePic(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.SetUserPicRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	status, err := h.svc.SetProfilePic(token, req.Username, req.ProfilePicURL)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	w.WriteHeader(status)
}

func (h *AuthHandler) DeleteUser(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	username := r.PathValue("username")
	if username == "" {
		http.Error(w, "缺少 username", http.StatusBadRequest)
		return
	}
	status, err := h.svc.DeleteUser(token, username)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	w.WriteHeader(status)
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
