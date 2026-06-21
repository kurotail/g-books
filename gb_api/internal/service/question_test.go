package service

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"gb-api/internal/model"
	"gb-api/internal/repo/mock"
)

// newQuestionSvc builds a QuestionSvc whose every user reports the given role — enough
// for the pool-management tests. Returns the service and its question repo mock.
func newQuestionSvc(role uint) (*QuestionSvc, *mock.QuestionRepo) {
	r := &mock.QuestionRepo{Sessions: map[string]model.QuestionSession{}}
	return NewQuestionSvc(r, &mock.RoleRepo{Role: role}), r
}

// newQuizSvc builds a TriggerSvc for caller "u" (role) assigned the given building
// (buildingID 0 = none) whose building (id 1) carries the given DifficultyType, and a
// question repo seeded with `questions`. The single mock.ItemRepo backs items, the
// inventory, and the attack-block store. Returns the service, its question repo, and
// its item repo.
func newQuizSvc(role, buildingID uint, difficultyType map[uint][]uint, questions map[uint]model.Question) (*TriggerSvc, *mock.QuestionRepo, *mock.ItemRepo) {
	r := &mock.QuestionRepo{Sessions: map[string]model.QuestionSession{}, Questions: questions}
	// "victim" is the attack-target user the QUIZ2 tests aim at; it must exist as a
	// real user for the username->id resolution to find its slots.
	users := &mock.AuthRepo{
		Roles:     map[string]uint{"u": role, "victim": model.RoleStudent},
		Buildings: map[string]uint{"u": buildingID},
	}
	buildings := &mock.BuildingRepo{Buildings: map[uint]model.Building{1: {ID: 1, DifficultyType: difficultyType}}}
	items := &mock.ItemRepo{Inv: map[uint]struct{}{}, Slot: map[uint]int{}, Items: map[uint]model.Item{}}
	return NewTriggerSvc(r, users, buildings, items, items, items, &mock.STTRepo{}), r, items
}

// idx is the wire form of an index answer the student submits to Answer: a single
// scalar index (the student always submits one value, even though the question's
// correct answer is a set).
func idx(i uint) json.RawMessage {
	b, _ := json.Marshal(i)
	return b
}

func accessTokenFor(t *testing.T, username string) string {
	t.Helper()
	tok, err := newTestAuthSvc().newAccessToken(mock.IDFor(username))
	if err != nil {
		t.Fatalf("failed to mint access token: %v", err)
	}
	return tok
}

// useState sets the package-level quiz state for the duration of a test and
// restores StateNormal afterwards.
func useState(t *testing.T, s model.ServerState) {
	t.Helper()
	stateCtl.setStateUntil(s, time.Time{})
	t.Cleanup(func() { stateCtl.setStateUntil(model.StateNormal, time.Time{}) })
}

// --- GenerateItem (QUIZ1 state) ---

// area1Q1 is an area-1, difficulty-1 question the item flow can draw.
var area1Q1 = map[uint]model.Question{
	1: {Content: model.TextContent("2+2?", "3", "4"), Answer: model.IndexAnswer(1), Difficulty: 1, Area: 1},
}

func TestQuestionSvc_GenerateItem_Succeeds(t *testing.T) {
	s, r, items := newQuizSvc(model.RoleTeacher, 1, map[uint][]uint{1: {10}}, area1Q1)

	data, status, err := s.GenerateItem(accessTokenFor(t, "u"), 1)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var raw map[string]any
	if err := json.Unmarshal(data, &raw); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if raw["session"] == nil || raw["content"] == nil {
		t.Error("expected session + content")
	}
	if _, leaked := raw["answer"]; leaked {
		t.Error("response must not leak the answer")
	}
	// An item was created and the stored session is a KindItem pointing at it.
	if len(items.Items) != 1 {
		t.Errorf("expected one created item, got %d", len(items.Items))
	}
	sess := r.Sessions[r.Created]
	if sess.Kind != model.KindItem || sess.ItemID == 0 || sess.UserID != mock.IDFor("u") {
		t.Errorf("expected a KindItem session for user u with an item, got %+v", sess)
	}
}

func TestQuestionSvc_GenerateItem_StudentForbiddenOutsideQuiz1(t *testing.T) {
	useState(t, model.StateQuiz2)
	s, _, _ := newQuizSvc(model.RoleStudent, 1, map[uint][]uint{1: {10}}, area1Q1)

	_, status, err := s.GenerateItem(accessTokenFor(t, "u"), 1)
	if err == nil {
		t.Fatal("expected error for student outside QUIZ1 state")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestQuestionSvc_GenerateItem_StudentForbiddenInNormal(t *testing.T) {
	// NORMAL is the default state; a student may not generate items there.
	s, _, _ := newQuizSvc(model.RoleStudent, 1, map[uint][]uint{1: {10}}, area1Q1)

	_, status, err := s.GenerateItem(accessTokenFor(t, "u"), 1)
	if err == nil {
		t.Fatal("expected error for student in NORMAL state")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestQuestionSvc_GenerateItem_StudentAllowedInQuiz1(t *testing.T) {
	useState(t, model.StateQuiz1)
	s, _, _ := newQuizSvc(model.RoleStudent, 1, map[uint][]uint{1: {10}}, area1Q1)

	_, status, err := s.GenerateItem(accessTokenFor(t, "u"), 1)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
}

func TestQuestionSvc_GenerateItem_NoBuilding(t *testing.T) {
	s, _, _ := newQuizSvc(model.RoleTeacher, 0, map[uint][]uint{1: {10}}, area1Q1)

	_, status, err := s.GenerateItem(accessTokenFor(t, "u"), 1)
	if err == nil {
		t.Fatal("expected error when caller has no building")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestQuestionSvc_GenerateItem_NoTypeForDifficulty(t *testing.T) {
	s, _, _ := newQuizSvc(model.RoleTeacher, 1, map[uint][]uint{1: {10}}, area1Q1)

	_, status, err := s.GenerateItem(accessTokenFor(t, "u"), 2) // building lists no type for difficulty 2
	if err == nil {
		t.Fatal("expected error when no type is available for the difficulty")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestQuestionSvc_GenerateItem_NoQuestion(t *testing.T) {
	s, _, _ := newQuizSvc(model.RoleTeacher, 1, map[uint][]uint{2: {10}}, area1Q1)

	_, status, err := s.GenerateItem(accessTokenFor(t, "u"), 2) // no area-1 difficulty-2 question
	if err == nil {
		t.Fatal("expected error when no matching question exists")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestQuestionSvc_GenerateItem_InvalidToken(t *testing.T) {
	s, _, _ := newQuizSvc(model.RoleAdmin, 1, map[uint][]uint{1: {10}}, area1Q1)

	_, status, err := s.GenerateItem("bad.token", 1)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

// --- GenerateTarget (QUIZ state) ---

// area2Q is an area-2 question the repair flow can draw.
var area2Q = map[uint]model.Question{
	5: {Content: model.TextContent("repair?", "yes", "no"), Answer: model.IndexAnswer(0), Difficulty: 1, Area: 2},
}

func TestQuestionSvc_GenerateTarget_AttackValid(t *testing.T) {
	useState(t, model.StateQuiz2)
	s, r, items := newQuizSvc(model.RoleStudent, 1, nil, area2Q)
	items.Slot[0] = 7 // target "victim" slot 0 holds normal item 7
	items.Items[7] = model.Item{ItemID: 7, Type: 10, QuestionID: 5}

	_, status, err := s.GenerateTarget(accessTokenFor(t, "u"), mock.IDFor("victim"), 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	sess := r.Sessions[r.Created]
	if sess.Kind != model.KindTarget || sess.Target == nil || sess.Target.UserID != mock.IDFor("victim") {
		t.Errorf("expected a KindTarget session at user victim, got %+v", sess)
	}
}

func TestQuestionSvc_GenerateTarget_RepairValid(t *testing.T) {
	useState(t, model.StateQuiz2)
	s, r, items := newQuizSvc(model.RoleStudent, 1, nil, area2Q)
	items.Slot[0] = -7 // own slot 0 holds a broken item
	// The broken item must resolve to a question so the repair quiz can match its
	// difficulty against an area-2 question (q5, difficulty 1).
	items.Items[7] = model.Item{ItemID: 7, Type: 10, QuestionID: 5}

	_, status, err := s.GenerateTarget(accessTokenFor(t, "u"), mock.IDFor("u"), 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	// The session records the area-2 repair question (q5) so a correct answer can bind it.
	if sess := r.Sessions[r.Created]; sess.QuestionID != 5 {
		t.Errorf("expected session to record repair question 5, got %d", sess.QuestionID)
	}
}

func TestQuestionSvc_GenerateTarget_InvalidTarget(t *testing.T) {
	useState(t, model.StateQuiz2)
	s, _, items := newQuizSvc(model.RoleStudent, 1, nil, area2Q)
	items.Slot[0] = -7 // broken item on ANOTHER person's board — neither attack nor repair
	// Note: no items.Items[7] — the target is classified invalid *before* any item lookup,
	// so it must report "無效的目標" rather than a missing-question error.

	_, status, err := s.GenerateTarget(accessTokenFor(t, "u"), mock.IDFor("victim"), 0)
	if err == nil {
		t.Fatal("expected error for an invalid target")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
	if err.Error() != "無效的目標" {
		t.Errorf("expected 無效的目標 (classified before lookup), got %q", err.Error())
	}
}

func TestQuestionSvc_GenerateTarget_EmptySlot(t *testing.T) {
	useState(t, model.StateQuiz2)
	s, _, _ := newQuizSvc(model.RoleStudent, 1, nil, area2Q)

	_, status, err := s.GenerateTarget(accessTokenFor(t, "u"), mock.IDFor("victim"), 0)
	if err == nil {
		t.Fatal("expected error for an empty slot")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestQuestionSvc_GenerateTarget_StudentForbiddenOutsideQuiz(t *testing.T) {
	s, _, items := newQuizSvc(model.RoleStudent, 1, nil, area2Q)
	items.Slot[0] = 7
	items.Items[7] = model.Item{ItemID: 7, QuestionID: 5}

	_, status, err := s.GenerateTarget(accessTokenFor(t, "u"), mock.IDFor("victim"), 0)
	if err == nil {
		t.Fatal("expected error for student outside QUIZ state")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

// --- Pool management (Upload / Search / Update / Delete) ---

func TestQuestionSvc_Upload_TeacherSucceeds(t *testing.T) {
	s, r := newQuestionSvc(model.RoleTeacher)

	inputs := []model.QuestionInput{
		{Content: model.TextContent("2+2?", "3", "4"), Answer: model.IndexAnswer(1)},
		{Content: model.TextContent("Capital of France?", "Paris", "Rome"), Answer: model.IndexAnswer(0)},
	}
	data, status, err := s.Upload(accessTokenFor(t, "teacher"), inputs)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusMultiStatus {
		t.Fatalf("expected 207, got %d", status)
	}
	var resp model.UploadQuestionsResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if len(resp.Results) != 2 {
		t.Fatalf("expected 2 results, got %d", len(resp.Results))
	}
	for i, res := range resp.Results {
		if res.Index != i {
			t.Errorf("result %d: expected index %d, got %d", i, i, res.Index)
		}
		if res.Status != http.StatusCreated {
			t.Errorf("result %d: expected 201, got %d", i, res.Status)
		}
		if res.ID == 0 {
			t.Errorf("result %d: expected a non-zero id", i)
		}
	}
	if resp.Results[0].ID == resp.Results[1].ID {
		t.Errorf("expected distinct ids, got %+v", resp.Results)
	}
	if len(r.Questions) != 2 {
		t.Errorf("expected pool to hold 2 questions, got %d", len(r.Questions))
	}
}

func TestQuestionSvc_Upload_PartialInvalidContinues(t *testing.T) {
	s, r := newQuestionSvc(model.RoleTeacher)

	inputs := []model.QuestionInput{
		{Content: model.TextContent("valid one", "a", "b"), Answer: model.IndexAnswer(1)},
		{Content: model.TextContent(""), Answer: model.IndexAnswer(0)}, // invalid: empty description
		{Content: model.TextContent("valid two", "a", "b", "c"), Answer: model.IndexAnswer(2)},
	}
	data, status, err := s.Upload(accessTokenFor(t, "teacher"), inputs)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusMultiStatus {
		t.Fatalf("expected 207, got %d", status)
	}
	var resp model.UploadQuestionsResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if len(resp.Results) != 3 {
		t.Fatalf("expected 3 results, got %d", len(resp.Results))
	}
	// The two valid questions are created; the empty one is rejected but does
	// not abort the batch.
	if resp.Results[0].Status != http.StatusCreated || resp.Results[0].ID == 0 {
		t.Errorf("result 0: expected created with id, got %+v", resp.Results[0])
	}
	if resp.Results[1].Status != http.StatusBadRequest || resp.Results[1].Error == "" {
		t.Errorf("result 1: expected 400 with error, got %+v", resp.Results[1])
	}
	if resp.Results[1].ID != 0 {
		t.Errorf("result 1: rejected question must not carry an id, got %d", resp.Results[1].ID)
	}
	if resp.Results[2].Status != http.StatusCreated || resp.Results[2].ID == 0 {
		t.Errorf("result 2: expected created with id, got %+v", resp.Results[2])
	}
	if len(r.Questions) != 2 {
		t.Errorf("expected pool to hold 2 questions, got %d", len(r.Questions))
	}
}

func TestQuestionSvc_Upload_StudentForbidden(t *testing.T) {
	s, _ := newQuestionSvc(model.RoleStudent)

	_, status, err := s.Upload(accessTokenFor(t, "student"),
		[]model.QuestionInput{{Content: model.TextContent("x", "a", "b"), Answer: model.IndexAnswer(0)}})
	if err == nil {
		t.Fatal("expected error for student upload")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestQuestionSvc_Upload_EmptyList(t *testing.T) {
	s, _ := newQuestionSvc(model.RoleTeacher)

	_, status, err := s.Upload(accessTokenFor(t, "teacher"), nil)
	if err == nil {
		t.Fatal("expected error for empty list")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestQuestionSvc_Upload_InvalidToken(t *testing.T) {
	s, _ := newQuestionSvc(model.RoleTeacher)

	_, status, err := s.Upload("bad.token",
		[]model.QuestionInput{{Content: model.TextContent("x", "a", "b"), Answer: model.IndexAnswer(0)}})
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestQuestionSvc_Search_ReturnsAllAndCarriesContent(t *testing.T) {
	s, r := newQuestionSvc(model.RoleTeacher)
	r.AddQuestions([]model.Question{
		{Content: model.TextContent("What is six times three?", "6", "18"), Answer: model.IndexAnswer(1)},
		{Content: model.TextContent("Capital of France?", "Paris", "Rome"), Answer: model.IndexAnswer(0)},
	})

	data, status, err := s.Search(accessTokenFor(t, "teacher"), nil, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var resp model.QuestionListResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if len(resp.Questions) != 2 {
		t.Fatalf("expected 2 questions, got %d", len(resp.Questions))
	}
	// Records carry the structured content (in ascending id order).
	if resp.Questions[0].Content.Description.Data != "What is six times three?" {
		t.Errorf("expected the first question's content, got %+v", resp.Questions[0].Content)
	}
}

func TestQuestionSvc_Search_FiltersByDifficultyAndArea(t *testing.T) {
	s, r := newQuestionSvc(model.RoleTeacher)
	r.AddQuestions([]model.Question{
		{Content: model.TextContent("easy algebra", "a", "b"), Answer: model.IndexAnswer(0), Difficulty: 1, Area: 7},
		{Content: model.TextContent("hard algebra", "a", "b"), Answer: model.IndexAnswer(0), Difficulty: 3, Area: 7},
		{Content: model.TextContent("hard geometry", "a", "b"), Answer: model.IndexAnswer(0), Difficulty: 3, Area: 9},
	})

	u := func(v uint) *uint { return &v }

	search := func(difficulty, area *uint) []model.QuestionRecord {
		t.Helper()
		data, status, err := s.Search(accessTokenFor(t, "teacher"), difficulty, area)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if status != http.StatusOK {
			t.Fatalf("expected 200, got %d", status)
		}
		var resp model.QuestionListResponse
		if err := json.Unmarshal(data, &resp); err != nil {
			t.Fatalf("invalid JSON: %v", err)
		}
		return resp.Questions
	}

	// difficulty only: the two hard questions.
	if got := search(u(3), nil); len(got) != 2 {
		t.Errorf("difficulty=3: expected 2, got %d (%+v)", len(got), got)
	}
	// area only: the two area-7 questions.
	if got := search(nil, u(7)); len(got) != 2 {
		t.Errorf("area=7: expected 2, got %d (%+v)", len(got), got)
	}
	// both: exact match on one question.
	got := search(u(3), u(7))
	if len(got) != 1 || got[0].Content.Description.Data != "hard algebra" {
		t.Errorf("difficulty=3&area=7: expected only 'hard algebra', got %+v", got)
	}
	if got[0].Difficulty != 3 || got[0].Area != 7 {
		t.Errorf("record must carry difficulty/area, got %+v", got[0])
	}
}

func TestQuestionSvc_Update_Succeeds(t *testing.T) {
	s, r := newQuestionSvc(model.RoleTeacher)
	created, _ := s.repo.AddQuestions([]model.Question{{Content: model.TextContent("old", "a", "b"), Answer: model.IndexAnswer(0)}})
	id := created[0].ID

	status, err := s.Update(accessTokenFor(t, "teacher"), id,
		model.QuestionInput{Content: model.TextContent("new", "a", "b", "c"), Answer: model.IndexAnswer(2)})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	got := r.Questions[id]
	var ans []uint
	json.Unmarshal(got.Answer.Data, &ans)
	if got.Content.Description.Data != "new" || len(ans) != 1 || ans[0] != 2 {
		t.Errorf("expected question to be updated, got %+v", got)
	}
}

func TestQuestionSvc_Update_NotFound(t *testing.T) {
	s, _ := newQuestionSvc(model.RoleTeacher)

	status, err := s.Update(accessTokenFor(t, "teacher"), 999,
		model.QuestionInput{Content: model.TextContent("x", "a", "b"), Answer: model.IndexAnswer(0)})
	if err == nil {
		t.Fatal("expected error for missing question")
	}
	if status != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", status)
	}
}

func TestQuestionSvc_Delete_Succeeds(t *testing.T) {
	s, r := newQuestionSvc(model.RoleTeacher)
	created, _ := s.repo.AddQuestions([]model.Question{{Content: model.TextContent("doomed", "a", "b"), Answer: model.IndexAnswer(0)}})
	id := created[0].ID

	status, err := s.Delete(accessTokenFor(t, "teacher"), id)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if _, ok := r.Questions[id]; ok {
		t.Error("expected question to be deleted")
	}
}

func TestQuestionSvc_Delete_NotFound(t *testing.T) {
	s, _ := newQuestionSvc(model.RoleTeacher)

	status, err := s.Delete(accessTokenFor(t, "teacher"), 999)
	if err == nil {
		t.Fatal("expected error for missing question")
	}
	if status != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", status)
	}
}

// --- Get (single question by id) ---

// A Student (no role gate) can fetch a question by id, answer included.
func TestQuestionSvc_Get_AnyRoleSucceeds(t *testing.T) {
	s, r := newQuestionSvc(model.RoleStudent)
	created, _ := r.AddQuestions([]model.Question{
		{Content: model.TextContent("2+2?", "3", "4"), Answer: model.IndexAnswer(1), Difficulty: 1, Area: 2},
	})
	id := created[0].ID

	data, status, err := s.Get(accessTokenFor(t, "student"), id)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var rec model.QuestionRecord
	if err := json.Unmarshal(data, &rec); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	var ans []uint
	json.Unmarshal(rec.Answer.Data, &ans)
	if rec.ID != id || rec.Content.Description.Data != "2+2?" || len(ans) != 1 || ans[0] != 1 {
		t.Errorf("unexpected record: %+v", rec)
	}
	if rec.Difficulty != 1 || rec.Area != 2 {
		t.Errorf("record must carry difficulty/area, got %+v", rec)
	}
}

func TestQuestionSvc_Get_NotFound(t *testing.T) {
	s, _ := newQuestionSvc(model.RoleStudent)

	_, status, err := s.Get(accessTokenFor(t, "student"), 999)
	if err == nil {
		t.Fatal("expected error for missing question")
	}
	if status != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", status)
	}
}

func TestQuestionSvc_Get_InvalidToken(t *testing.T) {
	s, _ := newQuestionSvc(model.RoleStudent)

	_, status, err := s.Get("bad.token", 1)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

// --- Answer ---

func TestQuestionSvc_Answer_ItemCorrectGrantsItem(t *testing.T) {
	s, r, items := newQuizSvc(model.RoleStudent, 1, nil, nil)
	r.Sessions["sid"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(time.Minute),
		UserID:    mock.IDFor("u"),
		Kind:      model.KindItem,
		ItemID:    42,
		Question:  model.Question{Answer: model.IndexAnswer(1)},
	}

	data, status, err := s.Answer(accessTokenFor(t, "u"), "sid", idx(1))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var resp model.AnswerResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if !resp.Correct || resp.ItemID != 42 {
		t.Errorf("expected correct with item_id 42, got %+v", resp)
	}
	if _, ok := items.Inv[42]; !ok {
		t.Error("expected item 42 added to the user's inventory")
	}
	if _, ok := r.Sessions["sid"]; ok {
		t.Error("expected session to be consumed")
	}
}

func TestQuestionSvc_Answer_ItemWrongGrantsNothing(t *testing.T) {
	s, r, items := newQuizSvc(model.RoleStudent, 1, nil, nil)
	r.Sessions["sid"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(time.Minute),
		UserID:    mock.IDFor("u"),
		Kind:      model.KindItem,
		ItemID:    42,
		Question:  model.Question{Answer: model.IndexAnswer(1)},
	}

	data, _, err := s.Answer(accessTokenFor(t, "u"), "sid", idx(3))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	var resp model.AnswerResponse
	json.Unmarshal(data, &resp)
	if resp.Correct {
		t.Error("expected correct=false")
	}
	if len(items.Inv) != 0 {
		t.Error("a wrong answer must not grant the item")
	}
}

// A question whose answer set holds several indexes grades any member correct and a
// non-member incorrect.
func TestQuestionSvc_Answer_ItemMultiIndexMatchesAnyMember(t *testing.T) {
	newSession := func(r *mock.QuestionRepo) {
		r.Sessions["sid"] = model.QuestionSession{
			ExpiresAt: time.Now().Add(time.Minute),
			UserID:    mock.IDFor("u"),
			Kind:      model.KindItem,
			ItemID:    42,
			Question:  model.Question{Answer: model.IndexAnswer(1, 3)},
		}
	}

	// Each accepted index grades correct.
	for _, want := range []uint{1, 3} {
		s, r, _ := newQuizSvc(model.RoleStudent, 1, nil, nil)
		newSession(r)
		data, _, err := s.Answer(accessTokenFor(t, "u"), "sid", idx(want))
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		var resp model.AnswerResponse
		json.Unmarshal(data, &resp)
		if !resp.Correct {
			t.Errorf("index %d: expected correct against answer set {1,3}", want)
		}
	}

	// A non-member grades incorrect.
	s, r, _ := newQuizSvc(model.RoleStudent, 1, nil, nil)
	newSession(r)
	data, _, err := s.Answer(accessTokenFor(t, "u"), "sid", idx(2))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	var resp model.AnswerResponse
	json.Unmarshal(data, &resp)
	if resp.Correct {
		t.Error("index 2: expected incorrect against answer set {1,3}")
	}
}

func TestQuestionSvc_Answer_TargetAttackBreaks(t *testing.T) {
	s, r, items := newQuizSvc(model.RoleStudent, 1, nil, nil)
	items.Slot[0] = 7 // "victim" board, normal item
	r.Sessions["sid"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(time.Minute),
		UserID:    mock.IDFor("u"),
		Kind:      model.KindTarget,
		Target:    &model.Target{UserID: mock.IDFor("victim"), SlotID: 0},
		Question:  model.Question{Answer: model.IndexAnswer(1)},
	}

	data, _, err := s.Answer(accessTokenFor(t, "u"), "sid", idx(1))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	var resp model.AnswerResponse
	json.Unmarshal(data, &resp)
	if !resp.Correct || resp.Success == nil || !*resp.Success {
		t.Errorf("expected correct with success=true, got %+v", resp)
	}
	if items.Slot[0] != -7 {
		t.Errorf("expected slot item broken (-7), got %d", items.Slot[0])
	}
}

func TestQuestionSvc_Answer_TargetAttackAlreadyBrokenFails(t *testing.T) {
	s, r, items := newQuizSvc(model.RoleStudent, 1, nil, nil)
	items.Slot[0] = -7 // already broken
	r.Sessions["sid"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(time.Minute),
		UserID:    mock.IDFor("u"),
		Kind:      model.KindTarget,
		Target:    &model.Target{UserID: mock.IDFor("victim"), SlotID: 0},
		Question:  model.Question{Answer: model.IndexAnswer(1)},
	}

	data, _, err := s.Answer(accessTokenFor(t, "u"), "sid", idx(1))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	var resp model.AnswerResponse
	json.Unmarshal(data, &resp)
	if !resp.Correct || resp.Success == nil || *resp.Success {
		t.Errorf("expected correct with success=false, got %+v", resp)
	}
	if items.Slot[0] != -7 {
		t.Errorf("slot must be unchanged, got %d", items.Slot[0])
	}
}

func TestQuestionSvc_Answer_TargetRepairFixes(t *testing.T) {
	s, r, items := newQuizSvc(model.RoleStudent, 1, nil, nil)
	items.Slot[0] = -7                                              // own broken item
	items.Items[7] = model.Item{ItemID: 7, Type: 10, QuestionID: 1} // its current question
	r.Sessions["sid"] = model.QuestionSession{
		ExpiresAt:  time.Now().Add(time.Minute),
		UserID:     mock.IDFor("u"),
		Kind:       model.KindTarget,
		Target:     &model.Target{UserID: mock.IDFor("u"), SlotID: 0},
		Question:   model.Question{Answer: model.IndexAnswer(1)},
		QuestionID: 42, // the answered repair question, to be bound to the item
	}

	data, _, err := s.Answer(accessTokenFor(t, "u"), "sid", idx(1))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	var resp model.AnswerResponse
	json.Unmarshal(data, &resp)
	if !resp.Correct || resp.Success == nil || !*resp.Success {
		t.Errorf("expected correct with success=true, got %+v", resp)
	}
	if items.Slot[0] != 7 {
		t.Errorf("expected slot item repaired (7), got %d", items.Slot[0])
	}
	// The answered question is bound to the repaired item.
	if items.Items[7].QuestionID != 42 {
		t.Errorf("expected repaired item 7 to bind question 42, got %d", items.Items[7].QuestionID)
	}
}

func TestQuestionSvc_Answer_TargetWrongNoAction(t *testing.T) {
	s, r, items := newQuizSvc(model.RoleStudent, 1, nil, nil)
	items.Slot[0] = 7
	r.Sessions["sid"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(time.Minute),
		UserID:    mock.IDFor("u"),
		Kind:      model.KindTarget,
		Target:    &model.Target{UserID: mock.IDFor("victim"), SlotID: 0},
		Question:  model.Question{Answer: model.IndexAnswer(1)},
	}

	data, _, err := s.Answer(accessTokenFor(t, "u"), "sid", idx(9)) // wrong
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	var resp model.AnswerResponse
	json.Unmarshal(data, &resp)
	if resp.Correct || resp.Success != nil {
		t.Errorf("expected correct=false and no success field, got %+v", resp)
	}
	if items.Slot[0] != 7 {
		t.Error("a wrong answer must not change the slot")
	}
}

// A failed attack bars the attacker from re-targeting the slot until it is repaired.
func TestQuestionSvc_Answer_FailedAttackBlocksRetarget(t *testing.T) {
	useState(t, model.StateQuiz2)
	s, r, items := newQuizSvc(model.RoleStudent, 1, nil, area2Q)
	items.Slot[0] = 7 // "victim" board, normal item
	items.Items[7] = model.Item{ItemID: 7, Type: 10, QuestionID: 5}
	r.Sessions["sid"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(time.Minute),
		UserID:    mock.IDFor("u"),
		Kind:      model.KindTarget,
		Target:    &model.Target{UserID: mock.IDFor("victim"), SlotID: 0},
		Question:  model.Question{Answer: model.IndexAnswer(1)},
	}

	// Wrong answer -> attack fails and the attacker is barred.
	data, _, err := s.Answer(accessTokenFor(t, "u"), "sid", idx(9))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	var resp model.AnswerResponse
	json.Unmarshal(data, &resp)
	if resp.Correct {
		t.Fatalf("expected the attack to fail, got %+v", resp)
	}
	if blocked, _ := items.IsAttackBlocked(mock.IDFor("victim"), 0, mock.IDFor("u")); !blocked {
		t.Fatal("expected the attacker to be recorded as blocked on the slot")
	}

	// Re-targeting the same slot is now rejected with 403.
	_, status, err := s.GenerateTarget(accessTokenFor(t, "u"), mock.IDFor("victim"), 0)
	if err == nil {
		t.Fatal("expected error re-attacking a slot the caller is barred from")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

// Repairing a slot lifts every attacker block on it.
func TestQuestionSvc_Answer_RepairClearsBlocks(t *testing.T) {
	s, r, items := newQuizSvc(model.RoleStudent, 1, nil, nil)
	items.Slot[0] = -7 // own broken item
	// "victim" was previously barred from attacking u's slot 0.
	items.AttackBlocks = map[[3]uint]struct{}{
		{mock.IDFor("u"), 0, mock.IDFor("victim")}: {},
	}
	r.Sessions["sid"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(time.Minute),
		UserID:    mock.IDFor("u"),
		Kind:      model.KindTarget,
		Target:    &model.Target{UserID: mock.IDFor("u"), SlotID: 0},
		Question:  model.Question{Answer: model.IndexAnswer(1)},
	}

	data, _, err := s.Answer(accessTokenFor(t, "u"), "sid", idx(1)) // correct repair
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	var resp model.AnswerResponse
	json.Unmarshal(data, &resp)
	if !resp.Correct || resp.Success == nil || !*resp.Success {
		t.Fatalf("expected a successful repair, got %+v", resp)
	}
	if items.Slot[0] != 7 {
		t.Errorf("expected slot repaired (7), got %d", items.Slot[0])
	}
	if blocked, _ := items.IsAttackBlocked(mock.IDFor("u"), 0, mock.IDFor("victim")); blocked {
		t.Error("expected the slot's attacker blocks to be cleared on repair")
	}
}

func TestQuestionSvc_Answer_UnknownSession(t *testing.T) {
	s, _, _ := newQuizSvc(model.RoleStudent, 1, nil, nil)

	_, status, err := s.Answer(accessTokenFor(t, "u"), "nope", idx(1))
	if err == nil {
		t.Fatal("expected error for unknown session")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestQuestionSvc_Answer_Expired(t *testing.T) {
	s, r, _ := newQuizSvc(model.RoleStudent, 1, nil, nil)
	r.Sessions["expired"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(-time.Minute),
		Question:  model.Question{Answer: model.IndexAnswer(1)},
	}

	_, status, err := s.Answer(accessTokenFor(t, "u"), "expired", idx(1))
	if err == nil {
		t.Fatal("expected error for expired session")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestQuestionSvc_Answer_InvalidToken(t *testing.T) {
	s, _, _ := newQuizSvc(model.RoleStudent, 1, nil, nil)

	_, status, err := s.Answer("bad.token", "session-id", idx(1))
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

// A voice_response answer is graded by transcribing the submitted audio URL (via the
// mock STT) and comparing case-insensitively to the question's expected transcript.
func TestQuestionSvc_Answer_VoiceResponseGradesViaSTT(t *testing.T) {
	r := &mock.QuestionRepo{Sessions: map[string]model.QuestionSession{}}
	users := &mock.AuthRepo{Roles: map[string]uint{"u": model.RoleStudent}, Buildings: map[string]uint{"u": 1}}
	items := &mock.ItemRepo{Inv: map[uint]struct{}{}, Slot: map[uint]int{}, Items: map[uint]model.Item{}}
	stt := &mock.STTRepo{Transcript: "Eighteen"} // returned regardless of the WAV bytes
	s := NewTriggerSvc(r, users, &mock.BuildingRepo{}, items, items, items, stt)

	// The student's answer is a base64-encoded WAV recording.
	wavB64 := base64.StdEncoding.EncodeToString([]byte("RIFF....WAVE fake audio"))
	audio, _ := json.Marshal(wavB64)

	// Transcript "Eighteen" matches the expected "eighteen" case-insensitively.
	r.Sessions["sid"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(time.Minute),
		UserID:    mock.IDFor("u"),
		Kind:      model.KindItem,
		ItemID:    42,
		Question:  model.Question{Answer: model.VoiceAnswer("eighteen")},
	}
	data, status, err := s.Answer(accessTokenFor(t, "u"), "sid", audio)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	var resp model.AnswerResponse
	json.Unmarshal(data, &resp)
	if !resp.Correct || resp.ItemID != 42 {
		t.Errorf("expected correct transcript match granting item, got %+v", resp)
	}
	if _, ok := items.Inv[42]; !ok {
		t.Error("expected item 42 added to inventory on a correct voice answer")
	}

	// A non-matching transcript grades incorrect.
	stt.Transcript = "nineteen"
	r.Sessions["sid2"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(time.Minute),
		UserID:    mock.IDFor("u"),
		Kind:      model.KindItem,
		ItemID:    43,
		Question:  model.Question{Answer: model.VoiceAnswer("eighteen")},
	}
	data, _, err = s.Answer(accessTokenFor(t, "u"), "sid2", audio)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	json.Unmarshal(data, &resp)
	if resp.Correct {
		t.Error("expected incorrect when the transcript does not match")
	}

	// An answer set with several accepted transcripts matches any member; here the
	// transcript "nineteen" matches the second accepted value.
	r.Sessions["sid3"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(time.Minute),
		UserID:    mock.IDFor("u"),
		Kind:      model.KindItem,
		ItemID:    44,
		Question:  model.Question{Answer: model.VoiceAnswer("eighteen", "nineteen")},
	}
	data, _, err = s.Answer(accessTokenFor(t, "u"), "sid3", audio)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	json.Unmarshal(data, &resp)
	if !resp.Correct {
		t.Error("expected correct when the transcript matches any accepted value")
	}
}
