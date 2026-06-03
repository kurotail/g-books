package service

import (
	"encoding/json"
	"net/http"
	"sync/atomic"
	"testing"
	"time"

	"gb-api/internal/model"
)

func clearRefreshTokens() {
	refreshTokens.Range(func(k, v any) bool {
		refreshTokens.Delete(k)
		return true
	})
}

// useAdvancingClock replaces now with a clock that advances by 1 s on every
// call, ensuring tokens minted in rapid succession always differ.
func useAdvancingClock(t *testing.T) {
	t.Helper()
	base := time.Now()
	var n atomic.Int64
	now = func() time.Time {
		return base.Add(time.Duration(n.Add(1)) * time.Second)
	}
	t.Cleanup(func() { now = time.Now })
}

func loginTokenPair(t *testing.T) map[string]string {
	t.Helper()
	data, _, err := LoginByName(model.Credential{Username: "user", Password: "password123"})
	if err != nil {
		t.Fatalf("login failed: %v", err)
	}
	var pair map[string]string
	if err := json.Unmarshal(data, &pair); err != nil {
		t.Fatalf("unmarshal failed: %v", err)
	}
	return pair
}

func TestLoginByName_ValidCredentials(t *testing.T) {
	t.Cleanup(clearRefreshTokens)
	useAdvancingClock(t)

	data, status, err := LoginByName(model.Credential{Username: "user", Password: "password123"})
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
	t.Cleanup(clearRefreshTokens)
	useAdvancingClock(t)

	_, status, err := LoginByName(model.Credential{Username: "user", Password: "wrong"})
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestLoginByName_WrongUsername(t *testing.T) {
	t.Cleanup(clearRefreshTokens)
	useAdvancingClock(t)

	_, status, err := LoginByName(model.Credential{Username: "nobody", Password: "password123"})
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestRefreshTokens_ValidToken(t *testing.T) {
	t.Cleanup(clearRefreshTokens)
	useAdvancingClock(t)

	pair := loginTokenPair(t)

	data, status, err := RefreshTokens(pair["refresh_token"])
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
	t.Cleanup(clearRefreshTokens)
	useAdvancingClock(t)

	pair := loginTokenPair(t)
	original := pair["refresh_token"]

	if _, _, err := RefreshTokens(original); err != nil {
		t.Fatalf("first use failed: %v", err)
	}

	_, status, err := RefreshTokens(original)
	if err == nil {
		t.Fatal("expected error on second use of same refresh token")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestRefreshTokens_ForgedToken(t *testing.T) {
	_, status, err := RefreshTokens("not.a.valid.token")
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestRefreshTokens_AccessTokenRejected(t *testing.T) {
	t.Cleanup(clearRefreshTokens)
	useAdvancingClock(t)

	pair := loginTokenPair(t)

	_, status, err := RefreshTokens(pair["access_token"])
	if err == nil {
		t.Fatal("expected error when using access token as refresh token")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestQueryDashboard_ValidAccessToken(t *testing.T) {
	t.Cleanup(clearRefreshTokens)
	useAdvancingClock(t)

	pair := loginTokenPair(t)

	data, status, err := QueryDashboard(pair["access_token"])
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if len(data) == 0 {
		t.Error("expected non-empty response body")
	}
}

func TestQueryDashboard_RefreshTokenRejected(t *testing.T) {
	t.Cleanup(clearRefreshTokens)
	useAdvancingClock(t)

	pair := loginTokenPair(t)

	_, status, err := QueryDashboard(pair["refresh_token"])
	if err == nil {
		t.Fatal("expected error when using refresh token on dashboard")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestQueryDashboard_InvalidToken(t *testing.T) {
	_, status, err := QueryDashboard("garbage")
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}
