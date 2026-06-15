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

// newQuestionSvc builds a QuestionSvc whose every user reports the given role (group
// 0), with empty group/building/item repos — enough for the pool-management and
// session-only tests. Returns the service and its question repo mock.
func newQuestionSvc(role uint) (*QuestionSvc, *mock.QuestionRepo) {
	r := &mock.QuestionRepo{Sessions: map[string]model.QuestionSession{}}
	return NewQuestionSvc(r, &mock.RoleRepo{Role: role}, &mock.GroupRepo{}, &mock.BuildingRepo{}, &mock.ItemRepo{}, &mock.STTRepo{}), r
}

// newQuizSvc builds a QuestionSvc for caller "u" (role + group), a building (id 1)
// assigned to that group with the given DifficultyType, and a question repo seeded with
// `questions`. Returns the service, its question repo, and its item repo.
func newQuizSvc(role, group uint, difficultyType map[uint][]uint, questions map[uint]model.Question) (*QuestionSvc, *mock.QuestionRepo, *mock.ItemRepo) {
	r := &mock.QuestionRepo{Sessions: map[string]model.QuestionSession{}, Questions: questions}
	users := &mock.AuthRepo{Roles: map[string]uint{"u": role}, Groups: map[string]uint{"u": group}}
	groups := &mock.GroupRepo{BuildingIDs: map[uint]uint{group: 1}}
	buildings := &mock.BuildingRepo{Buildings: map[uint]model.Building{1: {ID: 1, DifficultyType: difficultyType}}}
	items := &mock.ItemRepo{Inv: map[uint]struct{}{}, Slot: map[uint]int{}, Items: map[uint]model.Item{}}
	return NewQuestionSvc(r, users, groups, buildings, items, &mock.STTRepo{}), r, items
}

// idx is the wire form of an index answer the student submits to Answer.
func idx(i uint) json.RawMessage { return model.IndexAnswer(i).Data }

func accessTokenFor(t *testing.T, username string) string {
	t.Helper()
	tok, err := newTestAuthSvc().newAccessToken(username)
	if err != nil {
		t.Fatalf("failed to mint access token: %v", err)
	}
	return tok
}

// useState sets the package-level quiz state for the duration of a test and
// restores StateNormal afterwards.
func useState(t *testing.T, s model.ServerState) {
	t.Helper()
	setState(s)
	t.Cleanup(func() { setState(model.StateNormal) })
}

// --- GenerateItem (NORMAL state) ---

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
	if sess.Kind != model.KindItem || sess.ItemID == 0 || sess.GroupID != 1 {
		t.Errorf("expected a KindItem session for group 1 with an item, got %+v", sess)
	}
}

func TestQuestionSvc_GenerateItem_StudentForbiddenOutsideNormal(t *testing.T) {
	useState(t, model.StateQuiz2)
	s, _, _ := newQuizSvc(model.RoleStudent, 1, map[uint][]uint{1: {10}}, area1Q1)

	_, status, err := s.GenerateItem(accessTokenFor(t, "u"), 1)
	if err == nil {
		t.Fatal("expected error for student outside NORMAL state")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestQuestionSvc_GenerateItem_StudentAllowedInNormal(t *testing.T) {
	s, _, _ := newQuizSvc(model.RoleStudent, 1, map[uint][]uint{1: {10}}, area1Q1)

	_, status, err := s.GenerateItem(accessTokenFor(t, "u"), 1)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
}

func TestQuestionSvc_GenerateItem_NoGroup(t *testing.T) {
	s, _, _ := newQuizSvc(model.RoleTeacher, 0, map[uint][]uint{1: {10}}, area1Q1)

	_, status, err := s.GenerateItem(accessTokenFor(t, "u"), 1)
	if err == nil {
		t.Fatal("expected error when caller is in no group")
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
	items.Slot[0] = 7 // target group 2 slot 0 holds normal item 7
	items.Items[7] = model.Item{ItemID: 7, Type: 10, QuestionID: 5}

	_, status, err := s.GenerateTarget(accessTokenFor(t, "u"), 2, 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	sess := r.Sessions[r.Created]
	if sess.Kind != model.KindTarget || sess.Target == nil || sess.Target.GroupID != 2 {
		t.Errorf("expected a KindTarget session at group 2, got %+v", sess)
	}
}

func TestQuestionSvc_GenerateTarget_RepairValid(t *testing.T) {
	useState(t, model.StateQuiz2)
	s, _, items := newQuizSvc(model.RoleStudent, 1, nil, area2Q)
	items.Slot[0] = -7 // own group's slot 0 holds a broken item

	_, status, err := s.GenerateTarget(accessTokenFor(t, "u"), 1, 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
}

func TestQuestionSvc_GenerateTarget_InvalidTarget(t *testing.T) {
	useState(t, model.StateQuiz2)
	s, _, items := newQuizSvc(model.RoleStudent, 1, nil, area2Q)
	items.Slot[0] = -7 // broken item in ANOTHER group — neither attack nor repair

	_, status, err := s.GenerateTarget(accessTokenFor(t, "u"), 2, 0)
	if err == nil {
		t.Fatal("expected error for an invalid target")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestQuestionSvc_GenerateTarget_EmptySlot(t *testing.T) {
	useState(t, model.StateQuiz2)
	s, _, _ := newQuizSvc(model.RoleStudent, 1, nil, area2Q)

	_, status, err := s.GenerateTarget(accessTokenFor(t, "u"), 2, 0)
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

	_, status, err := s.GenerateTarget(accessTokenFor(t, "u"), 2, 0)
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
	var ans uint
	json.Unmarshal(got.Answer.Data, &ans)
	if got.Content.Description.Data != "new" || ans != 2 {
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

// --- Answer ---

func TestQuestionSvc_Answer_ItemCorrectGrantsItem(t *testing.T) {
	s, r, items := newQuizSvc(model.RoleStudent, 1, nil, nil)
	r.Sessions["sid"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(time.Minute),
		GroupID:   1,
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
		t.Error("expected item 42 added to the group's inventory")
	}
	if _, ok := r.Sessions["sid"]; ok {
		t.Error("expected session to be consumed")
	}
}

func TestQuestionSvc_Answer_ItemWrongGrantsNothing(t *testing.T) {
	s, r, items := newQuizSvc(model.RoleStudent, 1, nil, nil)
	r.Sessions["sid"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(time.Minute),
		GroupID:   1,
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

func TestQuestionSvc_Answer_TargetAttackBreaks(t *testing.T) {
	s, r, items := newQuizSvc(model.RoleStudent, 1, nil, nil)
	items.Slot[0] = 7 // target group 2, normal item
	r.Sessions["sid"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(time.Minute),
		GroupID:   1,
		Kind:      model.KindTarget,
		Target:    &model.Target{GroupID: 2, SlotID: 0},
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
		GroupID:   1,
		Kind:      model.KindTarget,
		Target:    &model.Target{GroupID: 2, SlotID: 0},
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
	items.Slot[0] = -7 // own group's broken item
	r.Sessions["sid"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(time.Minute),
		GroupID:   1,
		Kind:      model.KindTarget,
		Target:    &model.Target{GroupID: 1, SlotID: 0},
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
	if items.Slot[0] != 7 {
		t.Errorf("expected slot item repaired (7), got %d", items.Slot[0])
	}
}

func TestQuestionSvc_Answer_TargetWrongNoAction(t *testing.T) {
	s, r, items := newQuizSvc(model.RoleStudent, 1, nil, nil)
	items.Slot[0] = 7
	r.Sessions["sid"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(time.Minute),
		GroupID:   1,
		Kind:      model.KindTarget,
		Target:    &model.Target{GroupID: 2, SlotID: 0},
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
	users := &mock.AuthRepo{Roles: map[string]uint{"u": model.RoleStudent}, Groups: map[string]uint{"u": 1}}
	items := &mock.ItemRepo{Inv: map[uint]struct{}{}, Slot: map[uint]int{}, Items: map[uint]model.Item{}}
	stt := &mock.STTRepo{Transcript: "Eighteen"} // returned regardless of the WAV bytes
	s := NewQuestionSvc(r, users, &mock.GroupRepo{}, &mock.BuildingRepo{}, items, stt)

	// The student's answer is a base64-encoded WAV recording.
	wavB64 := base64.StdEncoding.EncodeToString([]byte("RIFF....WAVE fake audio"))
	audio, _ := json.Marshal(wavB64)

	// Transcript "Eighteen" matches the expected "eighteen" case-insensitively.
	r.Sessions["sid"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(time.Minute),
		GroupID:   1,
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
		GroupID:   1,
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
}
