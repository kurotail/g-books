package service

import (
	"encoding/json"
	"net/http"
	"sync/atomic"
	"testing"
	"time"

	"gb-api/internal/model"
	"gb-api/internal/repo/mock"
)

func newMockAuthRepo() *mock.AuthRepo {
	return &mock.AuthRepo{
		Users: map[string]string{"user": "password123"},
	}
}

func newTestAuthSvc() *AuthSvc {
	return NewAuthSvc(newMockAuthRepo())
}

func useAdvancingClock(t *testing.T) {
	t.Helper()
	base := time.Now()
	var n atomic.Int64
	now = func() time.Time {
		return base.Add(time.Duration(n.Add(1)) * time.Second)
	}
	t.Cleanup(func() { now = time.Now })
}

func loginTokenPair(t *testing.T, s *AuthSvc) map[string]string {
	t.Helper()
	data, _, err := s.LoginByName(model.Credential{Username: "user", Password: "password123"})
	if err != nil {
		t.Fatalf("login failed: %v", err)
	}
	var pair map[string]string
	if err := json.Unmarshal(data, &pair); err != nil {
		t.Fatalf("unmarshal failed: %v", err)
	}
	return pair
}

func TestAuthSvc_QueryUser_ValidToken(t *testing.T) {
	useAdvancingClock(t)
	s := newTestAuthSvc()

	data, status, err := s.QueryUser(validAccessToken(t))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var resp model.UsersResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if len(resp.Users) != 1 || resp.Users[0] != "user" {
		t.Errorf("expected users [user], got %v", resp.Users)
	}
}

func TestAuthSvc_QueryUser_InvalidToken(t *testing.T) {
	s := newTestAuthSvc()
	_, status, err := s.QueryUser("invalid.token")
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestLoginByName_ValidCredentials(t *testing.T) {
	useAdvancingClock(t)
	s := newTestAuthSvc()

	data, status, err := s.LoginByName(model.Credential{Username: "user", Password: "password123"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var resp map[string]string
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if resp["access_token"] == "" {
		t.Error("missing access_token")
	}
	if resp["refresh_token"] == "" {
		t.Error("missing refresh_token")
	}
}

func TestLoginByName_WrongPassword(t *testing.T) {
	useAdvancingClock(t)
	s := newTestAuthSvc()

	_, status, err := s.LoginByName(model.Credential{Username: "user", Password: "wrong"})
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestLoginByName_WrongUsername(t *testing.T) {
	useAdvancingClock(t)
	s := newTestAuthSvc()

	_, status, err := s.LoginByName(model.Credential{Username: "nobody", Password: "password123"})
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestRefreshTokens_ValidToken(t *testing.T) {
	useAdvancingClock(t)
	s := newTestAuthSvc()
	pair := loginTokenPair(t, s)

	data, status, err := s.RefreshTokens(pair["refresh_token"])
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var pair2 map[string]string
	if err := json.Unmarshal(data, &pair2); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if pair2["access_token"] == "" || pair2["refresh_token"] == "" {
		t.Error("missing tokens in response")
	}
	if pair2["refresh_token"] == pair["refresh_token"] {
		t.Error("rotated refresh token must differ from the original")
	}
}

func TestRefreshTokens_SingleUse(t *testing.T) {
	useAdvancingClock(t)
	s := newTestAuthSvc()
	original := loginTokenPair(t, s)["refresh_token"]

	if _, _, err := s.RefreshTokens(original); err != nil {
		t.Fatalf("first use failed: %v", err)
	}
	_, status, err := s.RefreshTokens(original)
	if err == nil {
		t.Fatal("expected error on second use of same refresh token")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestRefreshTokens_ForgedToken(t *testing.T) {
	s := newTestAuthSvc()

	_, status, err := s.RefreshTokens("not.a.valid.token")
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestRefreshTokens_AccessTokenRejected(t *testing.T) {
	useAdvancingClock(t)
	s := newTestAuthSvc()
	pair := loginTokenPair(t, s)

	_, status, err := s.RefreshTokens(pair["access_token"])
	if err == nil {
		t.Fatal("expected error when using access token as refresh token")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

