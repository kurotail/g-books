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
	question     *handler.QuestionHandler
	state        *handler.StateHandler
	authRepo     *mock.AuthRepo
	questionRepo *mock.QuestionRepo
}

func newFixture() *fixture {
	authRepo := &mock.AuthRepo{
		Users:     map[string]string{"user": "pass"},
		Roles:     map[string]uint{"user": model.RoleTeacher},
		Buildings: map[string]uint{"user": 1}, // user -> building 1
	}
	itemRepo := &mock.ItemRepo{
		Inv:  map[uint]struct{}{1: {}, 2: {}},
		Slot: map[uint]int{0: 3},
		Items: map[uint]model.Item{
			1: {ItemID: 1, Type: 10, QuestionID: 1},
			2: {ItemID: 2, Type: 20, QuestionID: 2},
			3: {ItemID: 3, Type: 10},
		},
		// Allowed is nil: every slot accepts every type, so the move-flow test
		// isn't coupled to a building.
	}
	buildingRepo := &mock.BuildingRepo{
		Buildings: map[uint]model.Building{
			1: {
				ID:              1,
				TypeAllowedSlot: map[uint][]uint{10: {0, 1, 5}, 20: {0, 1, 2, 5}},
				DifficultyType:  map[uint][]uint{1: {10}}, // difficulty 1 -> type 10 (for GenerateItem)
			},
		},
	}
	questionRepo := &mock.QuestionRepo{
		Sessions: map[string]model.QuestionSession{},
		Questions: map[uint]model.Question{
			1: {Content: model.TextContent("2+2?", "3", "4"), Answer: model.IndexAnswer(1), Difficulty: 1, Area: 1},
		},
	}
	return &fixture{
		auth:         handler.NewAuthHandler(service.NewAuthSvc(authRepo, authRepo)),
		item:         handler.NewItemHandler(service.NewItemSvc(itemRepo, itemRepo, authRepo, buildingRepo)),
		question:     handler.NewQuestionHandler(service.NewQuestionSvc(questionRepo, authRepo, buildingRepo, itemRepo, itemRepo, &mock.STTRepo{})),
		state:        handler.NewStateHandler(service.NewStateSvc(authRepo)),
		authRepo:     authRepo,
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

// decodeInv parses the item-query response inventory into a set keyed by item id.
func decodeInv(t *testing.T, rec *httptest.ResponseRecorder) map[uint]model.ItemView {
	t.Helper()
	var r struct {
		Inventory []model.ItemView `json:"inventory"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &r); err != nil {
		t.Fatalf("decodeInv: %v — body: %s", err, rec.Body.String())
	}
	out := make(map[uint]model.ItemView, len(r.Inventory))
	for _, v := range r.Inventory {
		out[v.ItemID] = v
	}
	return out
}

// decodeSlots parses the item-query response slots, keyed by slot id.
func decodeSlots(t *testing.T, rec *httptest.ResponseRecorder) map[uint]model.SlotView {
	t.Helper()
	var r struct {
		Slots map[uint]model.SlotView `json:"slots"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &r); err != nil {
		t.Fatalf("decodeSlots: %v — body: %s", err, rec.Body.String())
	}
	return r.Slots
}
