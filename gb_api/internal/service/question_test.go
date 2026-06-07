package service

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"gb-api/internal/model"
	"gb-api/internal/repo/mock"
)

// newQuestionSvc builds a QuestionSvc whose every user reports the given role,
// returning the service and its underlying question repo mock.
func newQuestionSvc(role uint) (*QuestionSvc, *mock.QuestionRepo) {
	r := &mock.QuestionRepo{Sessions: map[string]model.QuestionSession{}}
	return NewQuestionSvc(r, &mock.RoleRepo{Role: role}), r
}

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

// --- Generate ---

func TestQuestionSvc_Generate_TeacherSucceeds(t *testing.T) {
	s, _ := newQuestionSvc(model.RoleTeacher)

	data, status, err := s.Generate(accessTokenFor(t, "teacher"), 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	// Response must carry a session + description but never leak the answer.
	var raw map[string]any
	if err := json.Unmarshal(data, &raw); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if raw["session"] == "" || raw["session"] == nil {
		t.Error("expected a session in response")
	}
	if raw["description"] == nil {
		t.Error("expected a description in response")
	}
	if _, leaked := raw["Answer"]; leaked {
		t.Error("response must not contain the answer")
	}
	if _, leaked := raw["answer"]; leaked {
		t.Error("response must not contain the answer")
	}
}

func TestQuestionSvc_Generate_StudentForbiddenInNormal(t *testing.T) {
	s, _ := newQuestionSvc(model.RoleStudent)

	_, status, err := s.Generate(accessTokenFor(t, "student"), 0)
	if err == nil {
		t.Fatal("expected error for student in NORMAL state")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
}

func TestQuestionSvc_Generate_InvalidToken(t *testing.T) {
	s, _ := newQuestionSvc(model.RoleAdmin)

	_, status, err := s.Generate("bad.token", 0)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestQuestionSvc_Generate_StudentAllowedInQuizState(t *testing.T) {
	useState(t, model.StateQuiz)
	s, _ := newQuestionSvc(model.RoleStudent)

	_, status, err := s.Generate(accessTokenFor(t, "student"), 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
}

// --- Pool management (Upload / Search / Update / Delete) ---

func TestQuestionSvc_Upload_TeacherSucceeds(t *testing.T) {
	s, r := newQuestionSvc(model.RoleTeacher)

	inputs := []model.QuestionInput{
		{Description: "2+2?\n(a)3\n(b)4", Answer: 1},
		{Description: "Capital of France?\n(a)Paris\n(b)Rome", Answer: 0},
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
		{Description: "valid one", Answer: 1},
		{Description: "", Answer: 0}, // invalid: empty description
		{Description: "valid two", Answer: 2},
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
		[]model.QuestionInput{{Description: "x", Answer: 0}})
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
		[]model.QuestionInput{{Description: "x", Answer: 0}})
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}

func TestQuestionSvc_Search_FindsMatch(t *testing.T) {
	s, r := newQuestionSvc(model.RoleTeacher)
	r.AddQuestions([]model.Question{
		{Description: "What is six times three?", Answer: 1},
		{Description: "Capital of France?", Answer: 0},
	})

	data, status, err := s.Search(accessTokenFor(t, "teacher"), "france", nil, nil)
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
	if len(resp.Questions) != 1 || resp.Questions[0].Description != "Capital of France?" {
		t.Errorf("expected the France question, got %+v", resp.Questions)
	}
}

func TestQuestionSvc_Search_FiltersByDifficultyAndArea(t *testing.T) {
	s, r := newQuestionSvc(model.RoleTeacher)
	r.AddQuestions([]model.Question{
		{Description: "easy algebra", Answer: 0, Difficulty: 1, Area: 7},
		{Description: "hard algebra", Answer: 0, Difficulty: 3, Area: 7},
		{Description: "hard geometry", Answer: 0, Difficulty: 3, Area: 9},
	})

	u := func(v uint) *uint { return &v }

	search := func(query string, difficulty, area *uint) []model.QuestionRecord {
		t.Helper()
		data, status, err := s.Search(accessTokenFor(t, "teacher"), query, difficulty, area)
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
	if got := search("", u(3), nil); len(got) != 2 {
		t.Errorf("difficulty=3: expected 2, got %d (%+v)", len(got), got)
	}
	// area only: the two area-7 questions.
	if got := search("", nil, u(7)); len(got) != 2 {
		t.Errorf("area=7: expected 2, got %d (%+v)", len(got), got)
	}
	// both: exact match on one question.
	got := search("", u(3), u(7))
	if len(got) != 1 || got[0].Description != "hard algebra" {
		t.Errorf("difficulty=3&area=7: expected only 'hard algebra', got %+v", got)
	}
	if got[0].Difficulty != 3 || got[0].Area != 7 {
		t.Errorf("record must carry difficulty/area, got %+v", got[0])
	}
	// q AND-combines with the filters: substring excludes the geometry question.
	if got := search("geometry", u(3), nil); len(got) != 1 || got[0].Description != "hard geometry" {
		t.Errorf("q=geometry&difficulty=3: expected only 'hard geometry', got %+v", got)
	}
	if got := search("geometry", nil, u(7)); len(got) != 0 {
		t.Errorf("q=geometry&area=7: expected no match, got %+v", got)
	}
}

func TestQuestionSvc_Update_Succeeds(t *testing.T) {
	s, r := newQuestionSvc(model.RoleTeacher)
	created, _ := s.repo.AddQuestions([]model.Question{{Description: "old", Answer: 0}})
	id := created[0].ID

	status, err := s.Update(accessTokenFor(t, "teacher"), id,
		model.QuestionInput{Description: "new", Answer: 2})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
	if got := r.Questions[id]; got.Description != "new" || got.Answer != 2 {
		t.Errorf("expected question to be updated, got %+v", got)
	}
}

func TestQuestionSvc_Update_NotFound(t *testing.T) {
	s, _ := newQuestionSvc(model.RoleTeacher)

	status, err := s.Update(accessTokenFor(t, "teacher"), 999,
		model.QuestionInput{Description: "x", Answer: 0})
	if err == nil {
		t.Fatal("expected error for missing question")
	}
	if status != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", status)
	}
}

func TestQuestionSvc_Delete_Succeeds(t *testing.T) {
	s, r := newQuestionSvc(model.RoleTeacher)
	created, _ := s.repo.AddQuestions([]model.Question{{Description: "doomed", Answer: 0}})
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

func TestQuestionSvc_Answer_Correct(t *testing.T) {
	useState(t, model.StateQuiz) // let the student through the gate
	s, r := newQuestionSvc(model.RoleStudent)
	r.CreateSession(0) // seeds answer = 1
	id := r.Created

	data, status, err := s.Answer(accessTokenFor(t, "student"), id, 1)
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
	if !resp.Correct {
		t.Error("expected correct=true")
	}
	// Session must be deleted (single-use).
	if _, ok := r.Sessions[id]; ok {
		t.Error("expected session to be deleted after answering")
	}
}

func TestQuestionSvc_Answer_Wrong(t *testing.T) {
	useState(t, model.StateQuiz)
	s, r := newQuestionSvc(model.RoleStudent)
	r.CreateSession(0)
	id := r.Created

	data, status, err := s.Answer(accessTokenFor(t, "student"), id, 3)
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
	if resp.Correct {
		t.Error("expected correct=false")
	}
}

func TestQuestionSvc_Answer_StudentForbiddenInNormal(t *testing.T) {
	s, r := newQuestionSvc(model.RoleStudent)
	r.CreateSession(0)
	id := r.Created

	_, status, err := s.Answer(accessTokenFor(t, "student"), id, 1)
	if err == nil {
		t.Fatal("expected error for student in NORMAL state")
	}
	if status != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", status)
	}
	// The gate must reject before the session is consumed.
	if _, ok := r.Sessions[id]; !ok {
		t.Error("session must not be consumed when answering is forbidden")
	}
}

func TestQuestionSvc_Answer_TeacherAllowedInNormal(t *testing.T) {
	s, r := newQuestionSvc(model.RoleTeacher)
	r.CreateSession(0)
	id := r.Created

	_, status, err := s.Answer(accessTokenFor(t, "teacher"), id, 1)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d", status)
	}
}

func TestQuestionSvc_Answer_UnknownSession(t *testing.T) {
	useState(t, model.StateQuiz)
	s, _ := newQuestionSvc(model.RoleStudent)

	_, status, err := s.Answer(accessTokenFor(t, "student"), "nope", 1)
	if err == nil {
		t.Fatal("expected error for unknown session")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestQuestionSvc_Answer_Expired(t *testing.T) {
	useState(t, model.StateQuiz)
	s, r := newQuestionSvc(model.RoleStudent)
	r.Sessions["expired"] = model.QuestionSession{
		ExpiresAt: time.Now().Add(-time.Minute),
		Question:  model.Question{Answer: 1},
	}

	_, status, err := s.Answer(accessTokenFor(t, "student"), "expired", 1)
	if err == nil {
		t.Fatal("expected error for expired session")
	}
	if status != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", status)
	}
}

func TestQuestionSvc_Answer_InvalidToken(t *testing.T) {
	s, _ := newQuestionSvc(model.RoleStudent)

	_, status, err := s.Answer("bad.token", "session-id", 1)
	if err == nil {
		t.Fatal("expected error")
	}
	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", status)
	}
}
