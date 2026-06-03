package handler_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"

	"gb-api/internal/handler"
	"gb-api/internal/service"
)

// ---- mock repos ----

type mockAuthRepo struct {
	users         map[string]string
	refreshTokens sync.Map
}

func (m *mockAuthRepo) ValidateCredentials(username, password string) (bool, error) {
	stored, ok := m.users[username]
	return ok && stored == password, nil
}

func (m *mockAuthRepo) StoreRefreshToken(token string) error {
	m.refreshTokens.Store(token, struct{}{})
	return nil
}

func (m *mockAuthRepo) ConsumeRefreshToken(token string) (bool, error) {
	_, ok := m.refreshTokens.LoadAndDelete(token)
	return ok, nil
}

type mockItemRepo struct {
	inv  map[uint]uint
	slot map[uint]uint
}

func (m *mockItemRepo) QueryInv(_ uint) (map[uint]uint, error) {
	result := make(map[uint]uint, len(m.inv))
	for k, v := range m.inv {
		result[k] = v
	}
	return result, nil
}

func (m *mockItemRepo) QuerySlot(_ uint) (map[uint]uint, error) {
	result := make(map[uint]uint, len(m.slot))
	for k, v := range m.slot {
		result[k] = v
	}
	return result, nil
}

func (m *mockItemRepo) SetInv(_, itemID, itemCount uint) error {
	if itemCount == 0 {
		delete(m.inv, itemID)
	} else {
		m.inv[itemID] = itemCount
	}
	return nil
}

func (m *mockItemRepo) SetSlot(_, slotID, itemID uint) error {
	if itemID == 0 {
		delete(m.slot, slotID)
	} else {
		m.slot[slotID] = itemID
	}
	return nil
}

// ---- test fixture ----

type fixture struct {
	auth *handler.AuthHandler
	item *handler.ItemHandler
}

func newFixture() *fixture {
	authRepo := &mockAuthRepo{users: map[string]string{"user": "pass"}}
	itemRepo := &mockItemRepo{
		inv:  map[uint]uint{1: 3, 2: 1},
		slot: map[uint]uint{0: 1},
	}
	return &fixture{
		auth: handler.NewAuthHandler(service.NewAuthSvc(authRepo)),
		item: handler.NewItemHandler(service.NewItemSvc(itemRepo)),
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

// decodeMap parses a JSON object response into map[string]uint.
func decodeMap(t *testing.T, rec *httptest.ResponseRecorder) map[string]uint {
	t.Helper()
	var m map[string]uint
	if err := json.Unmarshal(rec.Body.Bytes(), &m); err != nil {
		t.Fatalf("decodeMap: %v — body: %s", err, rec.Body.String())
	}
	return m
}

// ---- auth handler tests ----

func TestAuthHandler_Login_ValidCredentials(t *testing.T) {
	f := newFixture()
	body, _ := json.Marshal(map[string]string{"username": "user", "password": "pass"})
	req := httptest.NewRequest(http.MethodPost, "/api/login", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	f.auth.Login(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("expected Content-Type application/json, got %s", ct)
	}
	var resp map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if resp["access_token"] == "" || resp["refresh_token"] == "" {
		t.Error("missing tokens in response")
	}
}

func TestAuthHandler_Login_WrongPassword(t *testing.T) {
	f := newFixture()
	body, _ := json.Marshal(map[string]string{"username": "user", "password": "wrong"})
	req := httptest.NewRequest(http.MethodPost, "/api/login", bytes.NewReader(body))
	rec := httptest.NewRecorder()

	f.auth.Login(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestAuthHandler_Login_InvalidJSON(t *testing.T) {
	f := newFixture()
	req := httptest.NewRequest(http.MethodPost, "/api/login", bytes.NewReader([]byte("not-json")))
	rec := httptest.NewRecorder()

	f.auth.Login(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
}

// ---- item handler: request validation ----

func TestItemHandler_MissingToken(t *testing.T) {
	f := newFixture()
	cases := map[string]http.HandlerFunc{
		"QueryInv":  f.item.QueryInv,
		"QuerySlot": f.item.QuerySlot,
	}
	for name, fn := range cases {
		rec := do(t, fn, "", map[string]any{"group_id": 0})
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s without token: expected 401, got %d", name, rec.Code)
		}
	}
}

func TestItemHandler_MissingFields(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	cases := []struct {
		name string
		fn   http.HandlerFunc
		body map[string]any
	}{
		{"DeleteSlotItem no slot_id", f.item.DeleteSlotItem, map[string]any{"group_id": 0}},
		{"IncreaseInvItem no item_id", f.item.IncreaseInvItem, map[string]any{"group_id": 0, "item_count": 1}},
		{"IncreaseInvItem no item_count", f.item.IncreaseInvItem, map[string]any{"group_id": 0, "item_id": 1}},
		{"TranInv2Slot no slot_id", f.item.TranInv2Slot, map[string]any{"group_id": 0, "item_id": 1}},
		{"TranInv2Slot no item_id", f.item.TranInv2Slot, map[string]any{"group_id": 0, "slot_id": 5}},
		{"TranSlot2Inv no slot_id", f.item.TranSlot2Inv, map[string]any{"group_id": 0}},
	}
	for _, c := range cases {
		rec := do(t, c.fn, tok, c.body)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s: expected 400, got %d", c.name, rec.Code)
		}
	}
}

// ---- item handler: state transition chain ----
//
// Initial:  inv={1:3, 2:1}  slot={0:1}
//
//  step 1  TranInv2Slot(item=1, slot=5)  -> inv={1:2, 2:1}  slot={0:1, 5:1}
//  step 2  QueryInv + QuerySlot          -> verify
//  step 3  TranSlot2Inv(slot=0)          -> inv={1:3, 2:1}  slot={5:1}
//  step 4  QueryInv + QuerySlot          -> verify
//  step 5  IncreaseInvItem(item=2, +3)   -> inv={1:3, 2:4}
//  step 6  DeleteSlotItem(slot=5)        -> slot={}
//  step 7  Final QueryInv + QuerySlot    -> verify

func TestItemHandler_StateTransitions(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	// step 1: move item 1 from inventory to slot 5
	rec := do(t, f.item.TranInv2Slot, tok, map[string]any{"group_id": 0, "item_id": 1, "slot_id": 5})
	if rec.Code != http.StatusOK {
		t.Fatalf("step1 TranInv2Slot: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// step 2: verify post-transfer state
	rec = do(t, f.item.QueryInv, tok, map[string]any{"group_id": 0})
	if rec.Code != http.StatusOK {
		t.Fatalf("step2 QueryInv: expected 200, got %d", rec.Code)
	}
	inv := decodeMap(t, rec)
	if inv["1"] != 2 {
		t.Errorf("step2: expected inv[1]==2, got %d", inv["1"])
	}
	if inv["2"] != 1 {
		t.Errorf("step2: expected inv[2]==1, got %d", inv["2"])
	}

	rec = do(t, f.item.QuerySlot, tok, map[string]any{"group_id": 0})
	if rec.Code != http.StatusOK {
		t.Fatalf("step2 QuerySlot: expected 200, got %d", rec.Code)
	}
	slot := decodeMap(t, rec)
	if slot["0"] != 1 {
		t.Errorf("step2: expected slot[0]==1, got %d", slot["0"])
	}
	if slot["5"] != 1 {
		t.Errorf("step2: expected slot[5]==1, got %d", slot["5"])
	}

	// step 3: return item from slot 0 to inventory (slot 0 held item 1)
	rec = do(t, f.item.TranSlot2Inv, tok, map[string]any{"group_id": 0, "slot_id": 0})
	if rec.Code != http.StatusOK {
		t.Fatalf("step3 TranSlot2Inv: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// step 4: verify slot 0 gone, inv[1] restored
	rec = do(t, f.item.QueryInv, tok, map[string]any{"group_id": 0})
	inv = decodeMap(t, rec)
	if inv["1"] != 3 {
		t.Errorf("step4: expected inv[1]==3, got %d", inv["1"])
	}

	rec = do(t, f.item.QuerySlot, tok, map[string]any{"group_id": 0})
	slot = decodeMap(t, rec)
	if _, ok := slot["0"]; ok {
		t.Error("step4: expected slot 0 to be removed")
	}
	if slot["5"] != 1 {
		t.Errorf("step4: expected slot[5]==1 (unchanged), got %d", slot["5"])
	}

	// step 5: add 3 more of item 2
	rec = do(t, f.item.IncreaseInvItem, tok, map[string]any{"group_id": 0, "item_id": 2, "item_count": 3})
	if rec.Code != http.StatusOK {
		t.Fatalf("step5 IncreaseInvItem: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	rec = do(t, f.item.QueryInv, tok, map[string]any{"group_id": 0})
	inv = decodeMap(t, rec)
	if inv["2"] != 4 {
		t.Errorf("step5: expected inv[2]==4, got %d", inv["2"])
	}

	// step 6: clear slot 5
	rec = do(t, f.item.DeleteSlotItem, tok, map[string]any{"group_id": 0, "slot_id": 5})
	if rec.Code != http.StatusOK {
		t.Fatalf("step6 DeleteSlotItem: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// step 7: final state — slot empty, inv={1:3, 2:4}
	rec = do(t, f.item.QuerySlot, tok, map[string]any{"group_id": 0})
	slot = decodeMap(t, rec)
	if len(slot) != 0 {
		t.Errorf("step7: expected empty slot map, got %v", slot)
	}

	rec = do(t, f.item.QueryInv, tok, map[string]any{"group_id": 0})
	inv = decodeMap(t, rec)
	if inv["1"] != 3 {
		t.Errorf("step7: expected inv[1]==3, got %d", inv["1"])
	}
	if inv["2"] != 4 {
		t.Errorf("step7: expected inv[2]==4, got %d", inv["2"])
	}
}

// ---- item handler: business rule violations ----

func TestItemHandler_TranInv2Slot_OutOfStock(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	rec := do(t, f.item.TranInv2Slot, tok, map[string]any{"group_id": 0, "item_id": 99, "slot_id": 5})
	if rec.Code != http.StatusBadRequest {
		t.Errorf("out-of-stock: expected 400, got %d", rec.Code)
	}
}

func TestItemHandler_TranSlot2Inv_NonExistentSlot(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	rec := do(t, f.item.TranSlot2Inv, tok, map[string]any{"group_id": 0, "slot_id": 99})
	if rec.Code != http.StatusBadRequest {
		t.Errorf("non-existent slot: expected 400, got %d", rec.Code)
	}
}
