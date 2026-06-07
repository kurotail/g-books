package handler_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"gb-api/internal/handler"
	"gb-api/internal/model"
	"gb-api/internal/repo/mock"
	"gb-api/internal/service"
)

// ---- test fixture ----

type fixture struct {
	auth         *handler.AuthHandler
	item         *handler.ItemHandler
	group        *handler.GroupHandler
	question     *handler.QuestionHandler
	state        *handler.StateHandler
	authRepo     *mock.AuthRepo
	groupRepo    *mock.GroupRepo
	questionRepo *mock.QuestionRepo
}

func newFixture() *fixture {
	// In production UserRepo and GroupRepo read/write the same users table; the
	// shared map mirrors that so SetGroup is visible to QueryGroup.
	groups := map[string]uint{"user": 1}
	authRepo := &mock.AuthRepo{
		Users:  map[string]string{"user": "pass"},
		Roles:  map[string]uint{"user": model.RoleTeacher},
		Groups: groups,
	}
	itemRepo := &mock.ItemRepo{
		Inv:  map[uint]uint{1: 3, 2: 1},
		Slot: map[uint]uint{0: 1},
	}
	groupRepo := &mock.GroupRepo{
		UserGroups: groups,
	}
	questionRepo := &mock.QuestionRepo{
		Sessions: map[string]model.QuestionSession{},
	}
	return &fixture{
		auth:         handler.NewAuthHandler(service.NewAuthSvc(authRepo, authRepo)),
		item:         handler.NewItemHandler(service.NewItemSvc(itemRepo)),
		group:        handler.NewGroupHandler(service.NewGroupSvc(groupRepo, authRepo)),
		question:     handler.NewQuestionHandler(service.NewQuestionSvc(questionRepo, authRepo)),
		state:        handler.NewStateHandler(service.NewStateSvc(authRepo)),
		authRepo:     authRepo,
		groupRepo:    groupRepo,
		questionRepo: questionRepo,
	}
}

// login calls POST /api/login and returns the access token.
func (f *fixture) login(t *testing.T) string {
	t.Helper()
	body, _ := json.Marshal(map[string]string{"username": "user", "password": "pass"})
	req := httptest.NewRequest(http.MethodPost, "/api/login", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	f.auth.Login(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("login: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("login: invalid JSON: %v", err)
	}
	tok := resp["access_token"]
	if tok == "" {
		t.Fatal("login: empty access_token")
	}
	return tok
}

// do sends a request to fn with a Bearer token and JSON body, returns the recorder.
func do(t *testing.T, fn http.HandlerFunc, token string, body map[string]any) *httptest.ResponseRecorder {
	t.Helper()
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	fn(rec, req)
	return rec
}

func doReq(t *testing.T, fn http.HandlerFunc, method, target, token string, body any, pathValues map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	var req *http.Request
	if body != nil {
		b, _ := json.Marshal(body)
		req = httptest.NewRequest(method, target, bytes.NewReader(b))
		req.Header.Set("Content-Type", "application/json")
	} else {
		req = httptest.NewRequest(method, target, nil)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	for k, v := range pathValues {
		req.SetPathValue(k, v)
	}
	rec := httptest.NewRecorder()
	fn(rec, req)
	return rec
}

// decodeMap parses a JSON object response into map[string]uint.
func decodeInv(t *testing.T, rec *httptest.ResponseRecorder) map[string]uint {
	t.Helper()
	var r struct {
		Inventory map[string]uint `json:"inventory"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &r); err != nil {
		t.Fatalf("decodeInv: %v — body: %s", err, rec.Body.String())
	}
	return r.Inventory
}

func decodeSlots(t *testing.T, rec *httptest.ResponseRecorder) map[string]uint {
	t.Helper()
	var r struct {
		Slots map[string]uint `json:"slots"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &r); err != nil {
		t.Fatalf("decodeSlots: %v — body: %s", err, rec.Body.String())
	}
	return r.Slots
}
