package service

import (
	"encoding/json"
	"net/http"
	"testing"

	"gb-api/internal/model"
	"gb-api/internal/repo/mock"
)

func newMockAuthRepo() *mock.AuthRepo {
	return &mock.AuthRepo{
		Users: map[string]string{"user": "password123"},
		Roles: map[string]uint{"user": model.RoleTeacher},
	}
}

func uptr(u uint) *uint { return &u }

func tokenFor(t *testing.T, username string) string {
	t.Helper()
	tok, err := newTestAuthSvc().newAccessToken(mock.IDFor(username))
	if err != nil {
		t.Fatalf("failed to mint access token: %v", err)
	}
	return tok
}

func newTestAuthSvc() *AuthSvc {
	r := newMockAuthRepo()
	return NewAuthSvc(r, r)
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

func TestAuthSvc_SetPassword_WrongCurrent(t *testing.T) {
	r := newMockAuthRepo()
	s := NewAuthSvc(r, r)

	status, err := s.SetPassword(tokenFor(t, "user"), "wrongpass", "newpass")
	if err == nil {
		t.Fatal("expected error for wrong current password")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
	if r.Users["user"] != "password123" {
		t.Errorf("password should be unchanged, got %q", r.Users["user"])
	}
}

func TestAuthSvc_SetPassword_Success(t *testing.T) {
	r := newMockAuthRepo()
	s := NewAuthSvc(r, r)

	status, err := s.SetPassword(tokenFor(t, "user"), "password123", "newpass")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if ok, _ := r.ValidateCredentials("user", "newpass"); !ok {
		t.Error("new password should validate")
	}
	if ok, _ := r.ValidateCredentials("user", "password123"); ok {
		t.Error("old password should no longer validate")
	}
}

func TestAuthSvc_SetUsername_Success(t *testing.T) {
	r := newMockAuthRepo()
	s := NewAuthSvc(r, r)

	status, err := s.SetUsername(tokenFor(t, "user"), "renamed")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if _, ok := r.Roles["renamed"]; !ok {
		t.Error("expected user reachable under new name")
	}
	if _, ok := r.Roles["user"]; ok {
		t.Error("expected old name to be gone")
	}
}

// TestAuthSvc_TokenSurvivesRename verifies the whole point of id-based tokens: an
// access token minted before a username change still authorizes afterward, with no
// re-login, because it carries the user's immutable id rather than the name.
func TestAuthSvc_TokenSurvivesRename(t *testing.T) {
	r := newMockAuthRepo()
	s := NewAuthSvc(r, r)

	token := tokenFor(t, "user") // minted before the rename

	if status, err := s.SetUsername(token, "renamed"); err != nil || status != http.StatusOK {
		t.Fatalf("rename failed: status=%d err=%v", status, err)
	}

	// Reuse the SAME token on an authenticated self-operation.
	status, err := s.SetProfilePic(token, nil, "/images/after.png")
	if err != nil {
		t.Fatalf("expected token to remain valid after rename, got error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200 after rename, got %d", status)
	}
	if r.Pics["renamed"] != "/images/after.png" {
		t.Errorf("expected pic set on renamed account, got %q", r.Pics["renamed"])
	}
}

func TestAuthSvc_SetUsername_Conflict(t *testing.T) {
	r := newMockAuthRepo()
	r.Users["taken"] = "pw"
	r.Roles["taken"] = model.RoleStudent
	s := NewAuthSvc(r, r)

	status, err := s.SetUsername(tokenFor(t, "user"), "taken")
	if err == nil {
		t.Fatal("expected error renaming to an existing username")
	}
	if status != http.StatusConflict {
		t.Fatalf("expected 409, got %d", status)
	}
}

func TestAuthSvc_QueryUser_ValidToken(t *testing.T) {
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
	if len(resp.Users) != 1 || resp.Users[0].Username != "user" {
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
	s := newTestAuthSvc()

	_, status, err := s.LoginByName(model.Credential{Username: "nobody", Password: "password123"})
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestRegisterUser_TeacherCreatesStudent(t *testing.T) {
	repo := newMockAuthRepo()
	s := NewAuthSvc(repo, repo)

	status, err := s.RegisterUser(tokenFor(t, "user"), "alice", "pw", model.RoleStudent)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusCreated {
		t.Fatalf("expected 201, got %d", status)
	}
	if repo.Users["alice"] != "pw" {
		t.Errorf("expected alice to be created with password pw, got %q", repo.Users["alice"])
	}
	if repo.Roles["alice"] != model.RoleStudent {
		t.Errorf("expected alice role %d, got %d", model.RoleStudent, repo.Roles["alice"])
	}
}

func TestRegisterUser_StudentForbidden(t *testing.T) {
	repo := newMockAuthRepo()
	repo.Roles["user"] = model.RoleStudent
	s := NewAuthSvc(repo, repo)

	status, err := s.RegisterUser(tokenFor(t, "user"), "alice", "pw", model.RoleStudent)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestRegisterUser_CannotCreateAdmin(t *testing.T) {
	s := newTestAuthSvc()

	status, err := s.RegisterUser(tokenFor(t, "user"), "alice", "pw", model.RoleAdmin)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestRegisterUser_DuplicateUser(t *testing.T) {
	s := newTestAuthSvc()

	status, err := s.RegisterUser(tokenFor(t, "user"), "user", "pw", model.RoleStudent)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusConflict {
		t.Fatalf("expected 409, got %d", status)
	}
}

func TestRegisterUser_InvalidToken(t *testing.T) {
	s := newTestAuthSvc()

	status, err := s.RegisterUser("invalid.token", "alice", "pw", model.RoleStudent)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

// newProfilePicAuthSvc returns an AuthSvc backed by a teacher and a couple of
// students, for exercising SetProfilePic authorization.
func newProfilePicAuthSvc() *AuthSvc {
	r := &mock.AuthRepo{
		Users: map[string]string{"teacher": "pw", "alice": "pw", "bob": "pw"},
		Roles: map[string]uint{
			"teacher": model.RoleTeacher,
			"alice":   model.RoleStudent,
			"bob":     model.RoleStudent,
		},
	}
	return NewAuthSvc(r, r)
}

func TestAuthSvc_SetProfilePic_SelfSucceeds(t *testing.T) {
	s := newProfilePicAuthSvc()

	status, err := s.SetProfilePic(tokenFor(t, "alice"), nil, "/images/alice.png")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	u, _ := s.users.GetUserByUsername("alice")
	if u.ProfilePicURL != "/images/alice.png" {
		t.Errorf("expected alice pic %q, got %q", "/images/alice.png", u.ProfilePicURL)
	}
}

func TestAuthSvc_SetProfilePic_StudentCannotSetOther(t *testing.T) {
	s := newProfilePicAuthSvc()

	status, err := s.SetProfilePic(tokenFor(t, "alice"), uptr(mock.IDFor("bob")), "/images/x.png")
	if err == nil {
		t.Fatal("expected error for student targeting another user")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestAuthSvc_SetProfilePic_TeacherSetsOther(t *testing.T) {
	s := newProfilePicAuthSvc()

	status, err := s.SetProfilePic(tokenFor(t, "teacher"), uptr(mock.IDFor("bob")), "/images/bob.png")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	u, _ := s.users.GetUserByUsername("bob")
	if u.ProfilePicURL != "/images/bob.png" {
		t.Errorf("expected bob pic %q, got %q", "/images/bob.png", u.ProfilePicURL)
	}
}

func TestAuthSvc_SetProfilePic_UnknownTarget(t *testing.T) {
	s := newProfilePicAuthSvc()

	status, err := s.SetProfilePic(tokenFor(t, "teacher"), uptr(999999999), "/images/x.png")
	if err == nil {
		t.Fatal("expected error for unknown target user")
	}
	if status != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", status)
	}
}

func TestAuthSvc_SetProfilePic_InvalidToken(t *testing.T) {
	s := newProfilePicAuthSvc()

	status, err := s.SetProfilePic("bad.token", nil, "/images/x.png")
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestAuthSvc_DeleteUser_TeacherDeletesStudent(t *testing.T) {
	s := newProfilePicAuthSvc()

	status, err := s.DeleteUser(accessTokenFor(t, "teacher"), mock.IDFor("alice"))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if _, err := s.users.GetUserByUsername("alice"); err == nil {
		t.Error("expected alice to be deleted")
	}
}

func TestAuthSvc_DeleteUser_UnknownTarget(t *testing.T) {
	s := newProfilePicAuthSvc()

	status, err := s.DeleteUser(accessTokenFor(t, "teacher"), 999999999)
	if err == nil {
		t.Fatal("expected error for unknown user")
	}
	if status != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", status)
	}
}

func TestAuthSvc_DeleteUser_StudentForbidden(t *testing.T) {
	s := newProfilePicAuthSvc()

	status, err := s.DeleteUser(accessTokenFor(t, "alice"), mock.IDFor("bob"))
	if err == nil {
		t.Fatal("expected error for student caller")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestAuthSvc_DeleteUser_SelfForbidden(t *testing.T) {
	s := newProfilePicAuthSvc()

	status, err := s.DeleteUser(accessTokenFor(t, "teacher"), mock.IDFor("teacher"))
	if err == nil {
		t.Fatal("expected error for self-deletion")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
	if _, err := s.users.GetUserByUsername("teacher"); err != nil {
		t.Error("expected teacher to still exist after blocked self-deletion")
	}
}

func TestAuthSvc_DeleteUser_InvalidToken(t *testing.T) {
	s := newProfilePicAuthSvc()

	status, err := s.DeleteUser("bad.token", mock.IDFor("alice"))
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestRefreshTokens_ValidToken(t *testing.T) {
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
