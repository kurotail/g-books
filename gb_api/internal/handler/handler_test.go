package handler_test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"gb-api/internal/model"
	"gb-api/internal/repo/mock"
)

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

// ---- auth handler: Register ----

func TestAuthHandler_Register_TeacherCreatesStudent(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	rec := do(t, f.auth.Register, tok, map[string]any{"username": "alice", "password": "pw", "role": 0})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	// the new user should now show up in QueryUser
	rec = do(t, f.auth.QueryUser, tok, nil)
	var ur model.UsersResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &ur); err != nil {
		t.Fatalf("QueryUser: invalid JSON: %v", err)
	}
	found := false
	for _, u := range ur.Users {
		if u.Username == "alice" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected alice in users, got %v", ur.Users)
	}
}

func TestAuthHandler_Register_TeacherCreatesTeacher(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	rec := do(t, f.auth.Register, tok, map[string]any{"username": "bob", "password": "pw", "role": 1})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	if f.authRepo.Roles["bob"] != model.RoleTeacher {
		t.Errorf("expected bob to be a teacher, got %d", f.authRepo.Roles["bob"])
	}
}

func TestAuthHandler_Register_StudentForbidden(t *testing.T) {
	f := newFixture()
	f.authRepo.Roles["user"] = model.RoleStudent
	tok := f.login(t)

	rec := do(t, f.auth.Register, tok, map[string]any{"username": "alice", "password": "pw", "role": 0})
	if rec.Code != http.StatusForbidden {
		t.Errorf("student caller: expected 403, got %d", rec.Code)
	}
}

func TestAuthHandler_Register_CannotCreateAdmin(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	rec := do(t, f.auth.Register, tok, map[string]any{"username": "root", "password": "pw", "role": 2})
	if rec.Code != http.StatusForbidden {
		t.Errorf("create admin: expected 403, got %d", rec.Code)
	}
}

func TestAuthHandler_Register_DuplicateUser(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	rec := do(t, f.auth.Register, tok, map[string]any{"username": "user", "password": "pw", "role": 0})
	if rec.Code != http.StatusConflict {
		t.Errorf("duplicate user: expected 409, got %d", rec.Code)
	}
}

func TestAuthHandler_Register_MissingToken(t *testing.T) {
	f := newFixture()
	rec := do(t, f.auth.Register, "", map[string]any{"username": "alice", "password": "pw", "role": 0})
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("missing token: expected 401, got %d", rec.Code)
	}
}

func TestAuthHandler_Register_MissingFields(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	cases := []struct {
		name string
		body map[string]any
	}{
		{"no username", map[string]any{"password": "pw", "role": 0}},
		{"no password", map[string]any{"username": "alice", "role": 0}},
		{"no role", map[string]any{"username": "alice", "password": "pw"}},
	}
	for _, c := range cases {
		rec := do(t, f.auth.Register, tok, c.body)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s: expected 400, got %d", c.name, rec.Code)
		}
	}
}

// ---- auth handler: GetUser (single lookup) ----

func TestAuthHandler_GetUser_FoundAndUnknown(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	rec := doReq(t, f.auth.GetUser, http.MethodGet, "/api/users/user", tok, nil, map[string]string{"username": "user"})
	if rec.Code != http.StatusOK {
		t.Fatalf("lookup existing user: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var u model.User
	if err := json.Unmarshal(rec.Body.Bytes(), &u); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if u.Username != "user" || u.ID != mock.IDFor("user") {
		t.Errorf("expected user with id %d, got %+v", mock.IDFor("user"), u)
	}

	rec = doReq(t, f.auth.GetUser, http.MethodGet, "/api/users/ghost", tok, nil, map[string]string{"username": "ghost"})
	if rec.Code != http.StatusNotFound {
		t.Errorf("lookup unknown user: expected 404, got %d", rec.Code)
	}

	rec = doReq(t, f.auth.GetUser, http.MethodGet, "/api/users/user", "", nil, map[string]string{"username": "user"})
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("lookup without token: expected 401, got %d", rec.Code)
	}
}

// ---- item handler: request validation ----

func TestItemHandler_MissingToken(t *testing.T) {
	f := newFixture()
	cases := map[string]http.HandlerFunc{
		"QueryItems": f.item.QueryItems,
	}
	for name, fn := range cases {
		rec := do(t, fn, "", map[string]any{"user_id": mock.IDFor("user")})
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
		{"TranInv2Slot no slot_id", f.item.TranInv2Slot, map[string]any{"user_id": mock.IDFor("user"), "item_id": 1}},
		{"TranInv2Slot no item_id", f.item.TranInv2Slot, map[string]any{"user_id": mock.IDFor("user"), "slot_id": 5}},
		{"TranSlot2Inv no slot_id", f.item.TranSlot2Inv, map[string]any{"user_id": mock.IDFor("user")}},
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
// Initial:  inv={1, 2}  slot={0:3}   (items 1,2,3; Allowed nil = any slot)
//
//  step 1  TranInv2Slot(item=1, slot=5)  -> inv={2}     slot={0:3, 5:1}
//  step 2  QueryItems                    -> verify
//  step 3  TranSlot2Inv(slot=0)          -> inv={2, 3}  slot={5:1}
//  step 4  QueryItems                    -> verify
//  step 5  TranSlot2Inv(slot=5)          -> inv={1, 2, 3}  slot={}
//  step 6  Final QueryItems              -> verify

func TestItemHandler_StateTransitions(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	// step 1: move item 1 from inventory to slot 5
	rec := do(t, f.item.TranInv2Slot, tok, map[string]any{"user_id": mock.IDFor("user"), "item_id": 1, "slot_id": 5})
	if rec.Code != http.StatusOK {
		t.Fatalf("step1 TranInv2Slot: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// step 2: item 1 left inventory and now sits in slot 5; item 3 still in slot 0
	rec = do(t, f.item.QueryItems, tok, map[string]any{"user_id": mock.IDFor("user")})
	if rec.Code != http.StatusOK {
		t.Fatalf("step2 QueryItems: expected 200, got %d", rec.Code)
	}
	inv := decodeInv(t, rec)
	if _, ok := inv[1]; ok {
		t.Error("step2: expected item 1 to leave inventory")
	}
	if _, ok := inv[2]; !ok {
		t.Error("step2: expected item 2 still in inventory")
	}
	slot := decodeSlots(t, rec)
	if slot[0].ItemID != 3 {
		t.Errorf("step2: expected slot[0] item 3, got %+v", slot[0])
	}
	if slot[5].ItemID != 1 {
		t.Errorf("step2: expected slot[5] item 1, got %+v", slot[5])
	}

	// step 3: return item from slot 0 to inventory (slot 0 held item 3)
	rec = do(t, f.item.TranSlot2Inv, tok, map[string]any{"user_id": mock.IDFor("user"), "slot_id": 0})
	if rec.Code != http.StatusOK {
		t.Fatalf("step3 TranSlot2Inv: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// step 4: slot 0 gone, item 3 back in inventory, slot 5 unchanged
	rec = do(t, f.item.QueryItems, tok, map[string]any{"user_id": mock.IDFor("user")})
	inv = decodeInv(t, rec)
	if _, ok := inv[3]; !ok {
		t.Error("step4: expected item 3 back in inventory")
	}
	slot = decodeSlots(t, rec)
	if _, ok := slot[0]; ok {
		t.Error("step4: expected slot 0 to be removed")
	}
	if slot[5].ItemID != 1 {
		t.Errorf("step4: expected slot[5] item 1 (unchanged), got %+v", slot[5])
	}

	// step 5: return item 1 from slot 5 to inventory, clearing the slot
	rec = do(t, f.item.TranSlot2Inv, tok, map[string]any{"user_id": mock.IDFor("user"), "slot_id": 5})
	if rec.Code != http.StatusOK {
		t.Fatalf("step5 TranSlot2Inv: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// step 6: final state — slots empty, inventory holds items 1, 2, 3
	rec = do(t, f.item.QueryItems, tok, map[string]any{"user_id": mock.IDFor("user")})
	slot = decodeSlots(t, rec)
	if len(slot) != 0 {
		t.Errorf("step6: expected empty slot map, got %v", slot)
	}
	inv = decodeInv(t, rec)
	for _, id := range []uint{1, 2, 3} {
		if _, ok := inv[id]; !ok {
			t.Errorf("step6: expected item %d in inventory, got %+v", id, inv)
		}
	}
}

// ---- item handler: business rule violations ----

func TestItemHandler_TranInv2Slot_ItemNotInInventory(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	rec := do(t, f.item.TranInv2Slot, tok, map[string]any{"user_id": mock.IDFor("user"), "item_id": 99, "slot_id": 5})
	if rec.Code != http.StatusBadRequest {
		t.Errorf("item not owned: expected 400, got %d", rec.Code)
	}
}

func TestItemHandler_TranSlot2Inv_NonExistentSlot(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	rec := do(t, f.item.TranSlot2Inv, tok, map[string]any{"user_id": mock.IDFor("user"), "slot_id": 99})
	if rec.Code != http.StatusBadRequest {
		t.Errorf("non-existent slot: expected 400, got %d", rec.Code)
	}
}

func TestItemHandler_QueryItems_MissingUsernameRejected(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	rec := do(t, f.item.QueryItems, tok, map[string]any{"user_id": 0})
	if rec.Code != http.StatusBadRequest {
		t.Errorf("empty username: expected 400, got %d", rec.Code)
	}
}

// ---- auth handler: SetBuilding ----

func TestAuthHandler_SetBuilding_Roundtrip(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	rec := do(t, f.auth.SetBuilding, tok, map[string]any{"building_id": 5})
	if rec.Code != http.StatusOK {
		t.Fatalf("SetBuilding: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if f.authRepo.Buildings["user"] != 5 {
		t.Errorf("expected user building 5, got %d", f.authRepo.Buildings["user"])
	}
}

func TestAuthHandler_SetBuilding_MissingBuildingID(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	rec := do(t, f.auth.SetBuilding, tok, map[string]any{})
	if rec.Code != http.StatusBadRequest {
		t.Errorf("missing building_id: expected 400, got %d", rec.Code)
	}
}

func TestAuthHandler_SetBuilding_MissingToken(t *testing.T) {
	f := newFixture()
	rec := do(t, f.auth.SetBuilding, "", map[string]any{"building_id": 5})
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("missing token: expected 401, got %d", rec.Code)
	}
}

// ---- auth handler: QueryUser ----

func TestAuthHandler_QueryUser(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	rec := do(t, f.auth.QueryUser, tok, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("QueryUser: expected 200, got %d", rec.Code)
	}
	var ur model.UsersResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &ur); err != nil {
		t.Fatalf("QueryUser: invalid JSON: %v", err)
	}
	if len(ur.Users) != 1 || ur.Users[0].Username != "user" {
		t.Errorf("expected users [user], got %v", ur.Users)
	}
}

func TestAuthHandler_QueryUser_MissingToken(t *testing.T) {
	f := newFixture()
	rec := do(t, f.auth.QueryUser, "", nil)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("QueryUser without token: expected 401, got %d", rec.Code)
	}
}

// ---- question handler: quiz state machine ----
//
// The quiz state is a package-level singleton in the service layer, so these
// tests drive it through the SetState handler and restore NORMAL on cleanup.
// State gate: students may only Generate/Answer while the state is QUIZ;
// teachers and admins always may.

// forceState sets the global quiz state via the SetState handler and resets to
// NORMAL on cleanup. The login user is a teacher (its role lives in authRepo, on
// which StateSvc depends), so the write is authorized regardless of the
// questionRepo role the question-gate tests may have set.
func (f *fixture) forceState(t *testing.T, tok string, s model.ServerState) {
	t.Helper()
	rec := do(t, f.state.SetState, tok, map[string]any{"state": string(s)})
	if rec.Code != http.StatusOK {
		t.Fatalf("forceState %q: expected 200, got %d: %s", s, rec.Code, rec.Body.String())
	}
	t.Cleanup(func() {
		do(t, f.state.SetState, tok, map[string]any{"state": string(model.StateNormal)})
	})
}

func TestQuestionHandler_MissingToken(t *testing.T) {
	f := newFixture()
	cases := map[string]http.HandlerFunc{
		"GenerateItem":   f.trigger.GenerateItem,
		"GenerateTarget": f.trigger.GenerateTarget,
		"Answer":         f.trigger.Answer,
		"GetState":       f.state.GetState,
		"SetState":       f.state.SetState,
	}
	for name, fn := range cases {
		rec := do(t, fn, "", map[string]any{"difficulty": 1, "state": "QUIZ"})
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s without token: expected 401, got %d", name, rec.Code)
		}
	}
}

func TestQuestionHandler_GetState_ReflectsTransitions(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	readState := func() model.ServerState {
		rec := do(t, f.state.GetState, tok, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("GetState: expected 200, got %d", rec.Code)
		}
		var resp model.StateResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("GetState: invalid JSON: %v", err)
		}
		return resp.State
	}

	f.forceState(t, tok, model.StateQuiz2)
	if got := readState(); got != model.StateQuiz2 {
		t.Errorf("after SetState QUIZ: expected QUIZ, got %q", got)
	}

	f.forceState(t, tok, model.StateNormal)
	if got := readState(); got != model.StateNormal {
		t.Errorf("after SetState NORMAL: expected NORMAL, got %q", got)
	}
}

func TestQuestionHandler_StudentItemBlockedOutsideQuiz1(t *testing.T) {
	f := newFixture()
	tok := f.login(t)
	f.forceState(t, tok, model.StateQuiz2)
	f.authRepo.Roles["user"] = model.RoleStudent

	gen := do(t, f.trigger.GenerateItem, tok, map[string]any{"difficulty": 1})
	if gen.Code != http.StatusForbidden {
		t.Errorf("GenerateItem as student outside QUIZ1: expected 403, got %d", gen.Code)
	}
}

func TestQuestionHandler_StudentTargetBlockedOutsideQuiz(t *testing.T) {
	f := newFixture()
	tok := f.login(t)
	f.forceState(t, tok, model.StateNormal)
	f.authRepo.Roles["user"] = model.RoleStudent

	gen := do(t, f.trigger.GenerateTarget, tok, map[string]any{"target_user_id": mock.IDFor("other"), "target_slot_id": 0})
	if gen.Code != http.StatusForbidden {
		t.Errorf("GenerateTarget as student in NORMAL: expected 403, got %d", gen.Code)
	}
}

// Item flow end-to-end at the handler level: a student in QUIZ1 earns an item by
// generating and answering correctly.
func TestQuestionHandler_ItemFlow(t *testing.T) {
	f := newFixture()
	tok := f.login(t)
	f.forceState(t, tok, model.StateQuiz1)
	f.authRepo.Roles["user"] = model.RoleStudent

	gen := do(t, f.trigger.GenerateItem, tok, map[string]any{"difficulty": 1})
	if gen.Code != http.StatusOK {
		t.Fatalf("GenerateItem: expected 200, got %d: %s", gen.Code, gen.Body.String())
	}
	var qr model.QuestionResponse
	if err := json.Unmarshal(gen.Body.Bytes(), &qr); err != nil {
		t.Fatalf("GenerateItem: invalid JSON: %v", err)
	}
	if qr.Session == "" {
		t.Fatal("GenerateItem: expected a session in response")
	}

	ans := do(t, f.trigger.Answer, tok, map[string]any{"session": qr.Session, "answer": 1})
	if ans.Code != http.StatusOK {
		t.Fatalf("Answer: expected 200, got %d: %s", ans.Code, ans.Body.String())
	}
	var ar model.AnswerResponse
	if err := json.Unmarshal(ans.Body.Bytes(), &ar); err != nil {
		t.Fatalf("Answer: invalid JSON: %v", err)
	}
	if !ar.Correct || ar.ItemID == 0 {
		t.Errorf("Answer: expected correct with a granted item_id, got %+v", ar)
	}
}

func TestQuestionHandler_SetState_StudentForbidden(t *testing.T) {
	f := newFixture()
	tok := f.login(t)
	f.authRepo.Roles["user"] = model.RoleStudent

	rec := do(t, f.state.SetState, tok, map[string]any{"state": "QUIZ1"})
	if rec.Code != http.StatusForbidden {
		t.Errorf("SetState as student: expected 403, got %d", rec.Code)
	}
}

// ---- question pool management handler tests ----

func uploadQuestions(t *testing.T, f *fixture, tok string, inputs []model.QuestionInput) []model.QuestionUploadResult {
	t.Helper()
	rec := doReq(t, f.question.Upload, http.MethodPost, "/api/question/upload", tok,
		model.UploadQuestionsRequest{Questions: inputs}, nil)
	if rec.Code != http.StatusMultiStatus {
		t.Fatalf("Upload: expected 207, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp model.UploadQuestionsResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("Upload: invalid JSON: %v", err)
	}
	if len(resp.Results) != len(inputs) {
		t.Fatalf("Upload: expected %d results, got %d", len(inputs), len(resp.Results))
	}
	return resp.Results
}

func createdIDs(results []model.QuestionUploadResult) []uint {
	ids := make([]uint, 0, len(results))
	for _, r := range results {
		if r.Status == http.StatusCreated {
			ids = append(ids, r.ID)
		}
	}
	return ids
}

// searchQuestions lists the pool via the search endpoint (no filters).
func searchQuestions(t *testing.T, f *fixture, tok string) []model.QuestionRecord {
	t.Helper()
	rec := doReq(t, f.question.Search, http.MethodGet, "/api/question/search", tok, nil, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("Search: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp model.QuestionListResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("Search: invalid JSON: %v", err)
	}
	return resp.Questions
}

func updateQuestion(t *testing.T, f *fixture, tok string, id uint, in model.QuestionInput) int {
	t.Helper()
	idStr := strconv.FormatUint(uint64(id), 10)
	rec := doReq(t, f.question.Update, http.MethodPut, "/api/question/"+idStr, tok, in,
		map[string]string{"id": idStr})
	return rec.Code
}

func deleteQuestion(t *testing.T, f *fixture, tok string, id uint) int {
	t.Helper()
	idStr := strconv.FormatUint(uint64(id), 10)
	rec := doReq(t, f.question.Delete, http.MethodDelete, "/api/question/"+idStr, tok, nil,
		map[string]string{"id": idStr})
	return rec.Code
}

func TestQuestionHandler_UploadAppendsRepeatedly(t *testing.T) {
	f := newFixture()
	tok := f.login(t) // "user" is a Teacher by fixture default

	total := 0
	for round := 1; round <= 3; round++ {
		inputs := []model.QuestionInput{
			{Content: model.TextContent(fmt.Sprintf("round %d q1", round), "x", "y"), Answer: model.IndexAnswer(0)},
			{Content: model.TextContent(fmt.Sprintf("round %d q2", round), "x", "y"), Answer: model.IndexAnswer(1)},
		}
		for i, r := range uploadQuestions(t, f, tok, inputs) {
			if r.Status != http.StatusCreated || r.ID == 0 {
				t.Errorf("round %d result %d: expected created with id, got %+v", round, i, r)
			}
		}
		total += len(inputs)
	}

	all := searchQuestions(t, f, tok)
	if len(all) != total {
		t.Errorf("expected %d questions in pool, got %d", total, len(all))
	}
	// IDs must stay unique across repeated appends.
	seen := map[uint]bool{}
	for _, q := range all {
		if seen[q.ID] {
			t.Errorf("duplicate id %d in pool", q.ID)
		}
		seen[q.ID] = true
	}
}

func TestQuestionHandler_UploadPartialInvalid(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	results := uploadQuestions(t, f, tok, []model.QuestionInput{
		{Content: model.TextContent("valid one", "a", "b"), Answer: model.IndexAnswer(0)},
		{Content: model.TextContent(""), Answer: model.IndexAnswer(0)}, // invalid: empty description
		{Content: model.TextContent("valid two", "a", "b"), Answer: model.IndexAnswer(1)},
	})
	if results[0].Status != http.StatusCreated || results[0].ID == 0 {
		t.Errorf("result 0: expected created with id, got %+v", results[0])
	}
	if results[1].Status != http.StatusBadRequest || results[1].Error == "" {
		t.Errorf("result 1: expected 400 with error, got %+v", results[1])
	}
	if results[2].Status != http.StatusCreated || results[2].ID == 0 {
		t.Errorf("result 2: expected created with id, got %+v", results[2])
	}
	if got := searchQuestions(t, f, tok); len(got) != 2 {
		t.Errorf("expected pool to hold 2 questions, got %d", len(got))
	}
}

func TestQuestionHandler_SearchFiltersByDifficultyAndArea(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	uploadQuestions(t, f, tok, []model.QuestionInput{
		{Content: model.TextContent("easy area7", "a", "b"), Answer: model.IndexAnswer(0), Difficulty: 1, Area: 7},
		{Content: model.TextContent("hard area7", "a", "b"), Answer: model.IndexAnswer(0), Difficulty: 3, Area: 7},
		{Content: model.TextContent("hard area9", "a", "b"), Answer: model.IndexAnswer(0), Difficulty: 3, Area: 9},
	})

	search := func(query string) []model.QuestionRecord {
		t.Helper()
		rec := doReq(t, f.question.Search, http.MethodGet, "/api/question/search"+query, tok, nil, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("Search(%q): expected 200, got %d: %s", query, rec.Code, rec.Body.String())
		}
		var resp model.QuestionListResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("Search(%q): invalid JSON: %v", query, err)
		}
		return resp.Questions
	}

	cases := []struct {
		query string
		want  int
	}{
		{"", 3}, // the 3 uploaded (ids 1-3 overwrite the fixture seed at id 1)
		{"?difficulty=3", 2},
		{"?area=7", 2},
		{"?difficulty=3&area=7", 1},
		{"?difficulty=3&area=9", 1},
		{"?area=99", 0},
	}
	for _, c := range cases {
		if got := search(c.query); len(got) != c.want {
			t.Errorf("search %q: expected %d matches, got %d (%+v)", c.query, c.want, len(got), got)
		}
	}
}

func TestQuestionHandler_UpdateSeveralTimes(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	ids := createdIDs(uploadQuestions(t, f, tok, []model.QuestionInput{
		{Content: model.TextContent("old one", "a", "b"), Answer: model.IndexAnswer(0)},
		{Content: model.TextContent("old two", "a", "b"), Answer: model.IndexAnswer(0)},
		{Content: model.TextContent("old three", "a", "b"), Answer: model.IndexAnswer(0)},
	}))
	if len(ids) != 3 {
		t.Fatalf("expected 3 created ids, got %d", len(ids))
	}

	for i, id := range ids {
		if code := updateQuestion(t, f, tok, id,
			model.QuestionInput{Content: model.TextContent(fmt.Sprintf("updated %d", i), "a", "b"), Answer: model.IndexAnswer(uint(i))}); code != http.StatusOK {
			t.Fatalf("Update id %d: expected 200, got %d", id, code)
		}
	}

	// The 3 uploaded questions (ids 1-3 overwrite the fixture seed) are all updated.
	if got := searchQuestions(t, f, tok); len(got) != 3 {
		t.Errorf("expected 3 questions, got %d", len(got))
	}

	// Updating a missing id returns 404; a non-numeric id returns 400.
	if code := updateQuestion(t, f, tok, 9999, model.QuestionInput{Content: model.TextContent("nope", "a", "b"), Answer: model.IndexAnswer(0)}); code != http.StatusNotFound {
		t.Errorf("Update missing id: expected 404, got %d", code)
	}
	bad := doReq(t, f.question.Update, http.MethodPut, "/api/question/abc", tok,
		model.QuestionInput{Content: model.TextContent("nope", "a", "b"), Answer: model.IndexAnswer(0)}, map[string]string{"id": "abc"})
	if bad.Code != http.StatusBadRequest {
		t.Errorf("Update non-numeric id: expected 400, got %d", bad.Code)
	}
}

func TestQuestionHandler_DeleteSeveralTimes(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	ids := createdIDs(uploadQuestions(t, f, tok, []model.QuestionInput{
		{Content: model.TextContent("doomed one", "a", "b"), Answer: model.IndexAnswer(0)},
		{Content: model.TextContent("doomed two", "a", "b"), Answer: model.IndexAnswer(0)},
		{Content: model.TextContent("doomed three", "a", "b"), Answer: model.IndexAnswer(0)},
	}))
	if len(ids) != 3 {
		t.Fatalf("expected 3 created ids, got %d", len(ids))
	}

	for _, id := range ids {
		if code := deleteQuestion(t, f, tok, id); code != http.StatusOK {
			t.Fatalf("Delete id %d: expected 200, got %d", id, code)
		}
		// Deleting the same id again returns 404.
		if code := deleteQuestion(t, f, tok, id); code != http.StatusNotFound {
			t.Errorf("Delete id %d twice: expected 404, got %d", id, code)
		}
	}

	// The uploads (ids 1-3) overwrote the fixture seed, so the pool is now empty.
	if remaining := searchQuestions(t, f, tok); len(remaining) != 0 {
		t.Errorf("expected empty pool after deletes, got %d", len(remaining))
	}
}

func TestQuestionHandler_PoolManagement_StudentForbidden(t *testing.T) {
	f := newFixture()
	tok := f.login(t)
	// Seed one question as a teacher, then demote the caller to Student.
	ids := createdIDs(uploadQuestions(t, f, tok, []model.QuestionInput{{Content: model.TextContent("seed", "a", "b"), Answer: model.IndexAnswer(0)}}))
	if len(ids) != 1 {
		t.Fatalf("expected 1 created id, got %d", len(ids))
	}
	id := ids[0]
	f.authRepo.Roles["user"] = model.RoleStudent

	upload := doReq(t, f.question.Upload, http.MethodPost, "/api/question/upload", tok,
		model.UploadQuestionsRequest{Questions: []model.QuestionInput{{Content: model.TextContent("x", "a", "b"), Answer: model.IndexAnswer(0)}}}, nil)
	if upload.Code != http.StatusForbidden {
		t.Errorf("student upload: expected 403, got %d", upload.Code)
	}
	search := doReq(t, f.question.Search, http.MethodGet, "/api/question/search", tok, nil, nil)
	if search.Code != http.StatusForbidden {
		t.Errorf("student search: expected 403, got %d", search.Code)
	}
	if code := updateQuestion(t, f, tok, id, model.QuestionInput{Content: model.TextContent("x", "a", "b"), Answer: model.IndexAnswer(0)}); code != http.StatusForbidden {
		t.Errorf("student update: expected 403, got %d", code)
	}
	if code := deleteQuestion(t, f, tok, id); code != http.StatusForbidden {
		t.Errorf("student delete: expected 403, got %d", code)
	}
	// Fetching a single question by id is NOT role-gated: the student may read it.
	idStr := strconv.FormatUint(uint64(id), 10)
	get := doReq(t, f.question.Get, http.MethodGet, "/api/question/"+idStr, tok, nil,
		map[string]string{"id": idStr})
	if get.Code != http.StatusOK {
		t.Errorf("student get by id: expected 200, got %d", get.Code)
	}
}

func TestQuestionHandler_GetByID(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	id := createdIDs(uploadQuestions(t, f, tok, []model.QuestionInput{
		{Content: model.TextContent("2+2?", "3", "4"), Answer: model.IndexAnswer(1), Difficulty: 1, Area: 2},
	}))[0]
	idStr := strconv.FormatUint(uint64(id), 10)

	// Found: the record carries content + answer.
	rec := doReq(t, f.question.Get, http.MethodGet, "/api/question/"+idStr, tok, nil,
		map[string]string{"id": idStr})
	if rec.Code != http.StatusOK {
		t.Fatalf("Get: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var got model.QuestionRecord
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("Get: invalid JSON: %v", err)
	}
	var ans []uint
	json.Unmarshal(got.Answer.Data, &ans)
	if got.ID != id || got.Content.Description.Data != "2+2?" || len(ans) != 1 || ans[0] != 1 {
		t.Errorf("unexpected record: %+v", got)
	}

	// Unknown id -> 404; non-numeric id -> 400.
	if miss := doReq(t, f.question.Get, http.MethodGet, "/api/question/9999", tok, nil,
		map[string]string{"id": "9999"}); miss.Code != http.StatusNotFound {
		t.Errorf("Get unknown id: expected 404, got %d", miss.Code)
	}
	if bad := doReq(t, f.question.Get, http.MethodGet, "/api/question/abc", tok, nil,
		map[string]string{"id": "abc"}); bad.Code != http.StatusBadRequest {
		t.Errorf("Get non-numeric id: expected 400, got %d", bad.Code)
	}
}
