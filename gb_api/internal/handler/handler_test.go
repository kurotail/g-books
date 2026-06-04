package handler_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"gb-api/internal/model"
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
		if u == "alice" {
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
//  step 5  TranSlot2Inv(slot=5)          -> inv={1:4, 2:1}  slot={}
//  step 6  Final QueryInv + QuerySlot    -> verify

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

	// step 5: return item 1 from slot 5 to inventory, clearing the slot
	rec = do(t, f.item.TranSlot2Inv, tok, map[string]any{"group_id": 0, "slot_id": 5})
	if rec.Code != http.StatusOK {
		t.Fatalf("step5 TranSlot2Inv: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// step 6: final state — slot empty, inv={1:4, 2:1}
	rec = do(t, f.item.QuerySlot, tok, map[string]any{"group_id": 0})
	slot = decodeMap(t, rec)
	if len(slot) != 0 {
		t.Errorf("step6: expected empty slot map, got %v", slot)
	}

	rec = do(t, f.item.QueryInv, tok, map[string]any{"group_id": 0})
	inv = decodeMap(t, rec)
	if inv["1"] != 4 {
		t.Errorf("step6: expected inv[1]==4, got %d", inv["1"])
	}
	if inv["2"] != 1 {
		t.Errorf("step6: expected inv[2]==1, got %d", inv["2"])
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

// ---- group handler ----

func TestGroupHandler_MissingToken(t *testing.T) {
	f := newFixture()
	cases := map[string]http.HandlerFunc{
		"SetGroup":    f.group.SetGroup,
		"QueryGroup":  f.group.QueryGroup,
		"QueryMember": f.group.QueryMember,
	}
	for name, fn := range cases {
		rec := do(t, fn, "", map[string]any{"group_id": 0, "username": "user"})
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s without token: expected 401, got %d", name, rec.Code)
		}
	}
}

func TestGroupHandler_SetGroup_MissingUsername(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	rec := do(t, f.group.SetGroup, tok, map[string]any{"group_id": 3})
	if rec.Code != http.StatusBadRequest {
		t.Errorf("missing username: expected 400, got %d", rec.Code)
	}
}

func TestGroupHandler_SetGroup_StudentForbidden(t *testing.T) {
	f := newFixture()
	f.groupRepo.Roles["user"] = model.RoleStudent
	tok := f.login(t)

	rec := do(t, f.group.SetGroup, tok, map[string]any{"group_id": 3, "username": "user"})
	if rec.Code != http.StatusForbidden {
		t.Errorf("student caller: expected 403, got %d", rec.Code)
	}
}

func TestGroupHandler_SetThenQueryRoundtrip(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	// teacher "user" reassigns itself to group 7
	rec := do(t, f.group.SetGroup, tok, map[string]any{"group_id": 7, "username": "user"})
	if rec.Code != http.StatusOK {
		t.Fatalf("SetGroup: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// QueryGroup should now report group 7
	rec = do(t, f.group.QueryGroup, tok, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("QueryGroup: expected 200, got %d", rec.Code)
	}
	var gr model.GroupResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &gr); err != nil {
		t.Fatalf("QueryGroup: invalid JSON: %v", err)
	}
	if gr.GroupID != 7 {
		t.Errorf("expected group_id 7, got %d", gr.GroupID)
	}

	// QueryMember(7) should list "user"
	rec = do(t, f.group.QueryMember, tok, map[string]any{"group_id": 7})
	if rec.Code != http.StatusOK {
		t.Fatalf("QueryMember: expected 200, got %d", rec.Code)
	}
	var mr model.MembersResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &mr); err != nil {
		t.Fatalf("QueryMember: invalid JSON: %v", err)
	}
	if len(mr.Members) != 1 || mr.Members[0] != "user" {
		t.Errorf("expected members [user], got %v", mr.Members)
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
	if len(ur.Users) != 1 || ur.Users[0] != "user" {
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

// forceState sets the global quiz state via the SetState handler (which needs a
// teacher), then restores the prior role and resets to NORMAL on cleanup.
func (f *fixture) forceState(t *testing.T, tok string, s model.ServerState) {
	t.Helper()
	prevRole := f.questionRepo.Role
	f.questionRepo.Role = model.RoleTeacher
	rec := do(t, f.question.SetState, tok, map[string]any{"state": string(s)})
	if rec.Code != http.StatusOK {
		t.Fatalf("forceState %q: expected 200, got %d: %s", s, rec.Code, rec.Body.String())
	}
	f.questionRepo.Role = prevRole
	t.Cleanup(func() {
		f.questionRepo.Role = model.RoleTeacher
		do(t, f.question.SetState, tok, map[string]any{"state": string(model.StateNormal)})
	})
}

func TestQuestionHandler_MissingToken(t *testing.T) {
	f := newFixture()
	cases := map[string]http.HandlerFunc{
		"Generate": f.question.Generate,
		"Answer":   f.question.Answer,
		"GetState": f.question.GetState,
		"SetState": f.question.SetState,
	}
	for name, fn := range cases {
		rec := do(t, fn, "", map[string]any{"group_id": 0, "state": "QUIZ"})
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s without token: expected 401, got %d", name, rec.Code)
		}
	}
}

func TestQuestionHandler_GetState_ReflectsTransitions(t *testing.T) {
	f := newFixture()
	tok := f.login(t)

	readState := func() model.ServerState {
		rec := do(t, f.question.GetState, tok, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("GetState: expected 200, got %d", rec.Code)
		}
		var resp model.StateResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("GetState: invalid JSON: %v", err)
		}
		return resp.State
	}

	f.forceState(t, tok, model.StateQuiz)
	if got := readState(); got != model.StateQuiz {
		t.Errorf("after SetState QUIZ: expected QUIZ, got %q", got)
	}

	f.forceState(t, tok, model.StateNormal)
	if got := readState(); got != model.StateNormal {
		t.Errorf("after SetState NORMAL: expected NORMAL, got %q", got)
	}
}

func TestQuestionHandler_StudentBlockedInNormalState(t *testing.T) {
	f := newFixture()
	tok := f.login(t)
	f.forceState(t, tok, model.StateNormal)
	f.questionRepo.Role = model.RoleStudent

	gen := do(t, f.question.Generate, tok, map[string]any{"group_id": 0})
	if gen.Code != http.StatusForbidden {
		t.Errorf("Generate as student in NORMAL: expected 403, got %d", gen.Code)
	}
	ans := do(t, f.question.Answer, tok, map[string]any{"session": "session-id", "answer": 1})
	if ans.Code != http.StatusForbidden {
		t.Errorf("Answer as student in NORMAL: expected 403, got %d", ans.Code)
	}
}

func TestQuestionHandler_StudentAllowedInQuizState(t *testing.T) {
	f := newFixture()
	tok := f.login(t)
	f.forceState(t, tok, model.StateQuiz)
	f.questionRepo.Role = model.RoleStudent

	gen := do(t, f.question.Generate, tok, map[string]any{"group_id": 0})
	if gen.Code != http.StatusOK {
		t.Fatalf("Generate as student in QUIZ: expected 200, got %d: %s", gen.Code, gen.Body.String())
	}
	var qr model.QuestionResponse
	if err := json.Unmarshal(gen.Body.Bytes(), &qr); err != nil {
		t.Fatalf("Generate: invalid JSON: %v", err)
	}
	if qr.Session == "" {
		t.Fatal("Generate: expected a session in response")
	}

	ans := do(t, f.question.Answer, tok, map[string]any{"session": qr.Session, "answer": 1})
	if ans.Code != http.StatusOK {
		t.Fatalf("Answer as student in QUIZ: expected 200, got %d: %s", ans.Code, ans.Body.String())
	}
	var ar model.AnswerResponse
	if err := json.Unmarshal(ans.Body.Bytes(), &ar); err != nil {
		t.Fatalf("Answer: invalid JSON: %v", err)
	}
	if !ar.Correct {
		t.Error("Answer: expected correct=true for answer 1")
	}
}

func TestQuestionHandler_TeacherAllowedInNormalState(t *testing.T) {
	f := newFixture()
	tok := f.login(t)
	f.forceState(t, tok, model.StateNormal)
	// role stays RoleTeacher (fixture default)

	gen := do(t, f.question.Generate, tok, map[string]any{"group_id": 0})
	if gen.Code != http.StatusOK {
		t.Errorf("Generate as teacher in NORMAL: expected 200, got %d: %s", gen.Code, gen.Body.String())
	}
}

func TestQuestionHandler_SetState_StudentForbidden(t *testing.T) {
	f := newFixture()
	tok := f.login(t)
	f.questionRepo.Role = model.RoleStudent

	rec := do(t, f.question.SetState, tok, map[string]any{"state": "QUIZ"})
	if rec.Code != http.StatusForbidden {
		t.Errorf("SetState as student: expected 403, got %d", rec.Code)
	}
}
