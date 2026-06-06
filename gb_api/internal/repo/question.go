package repo

import (
	crand "crypto/rand"
	"encoding/hex"
	mrand "math/rand"
	"sort"
	"strings"
	"time"

	apperr "gb-api/internal/error"
	"gb-api/internal/model"
)

const sessionTTL = 15 * time.Minute

type QuestionRepo interface {
	// CreateSession picks a random question, stores a single-use session for it,
	// and returns the session ID together with the picked question.
	CreateSession(groupID uint) (string, model.Question, error)
	// ConsumeSession loads and deletes a session. ok is false when absent.
	ConsumeSession(session string) (model.QuestionSession, bool, error)
	// AddQuestions appends questions to the pool, assigning each a new id, and
	// returns the created records.
	AddQuestions(qs []model.Question) ([]model.QuestionRecord, error)
	// SearchQuestions returns pool questions whose description contains query
	// (case-insensitive); an empty query returns all, sorted by id.
	SearchQuestions(query string) ([]model.QuestionRecord, error)
	// UpdateQuestion overwrites the question with the given id. ok is false when
	// no such question exists.
	UpdateQuestion(id uint, q model.Question) (bool, error)
	// DeleteQuestion removes the question with the given id. ok is false when no
	// such question exists.
	DeleteQuestion(id uint) (bool, error)
}

type questionRepo struct{}

func newSessionID() (string, error) {
	b := make([]byte, 16)
	if _, err := crand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func (_ *questionRepo) CreateSession(groupID uint) (string, model.Question, error) {
	id, err := newSessionID()
	if err != nil {
		return "", model.Question{}, err
	}
	db.mu.Lock()
	defer db.mu.Unlock()
	q, ok := randomQuestion()
	if !ok {
		return "", model.Question{}, apperr.ErrNoQuestions
	}
	db.sessions[id] = model.QuestionSession{
		ExpiresAt: time.Now().Add(sessionTTL),
		GroupID:   groupID,
		Question:  q,
	}
	return id, q, nil
}

// randomQuestion returns a uniformly random question from the pool. ok is false
// when the pool is empty. Callers must hold at least db.mu.RLock.
func randomQuestion() (model.Question, bool) {
	n := len(db.questions)
	if n == 0 {
		return model.Question{}, false
	}
	pick := mrand.Intn(n)
	i := 0
	for _, q := range db.questions {
		if i == pick {
			return q, true
		}
		i++
	}
	return model.Question{}, false
}

func (_ *questionRepo) AddQuestions(qs []model.Question) ([]model.QuestionRecord, error) {
	db.mu.Lock()
	defer db.mu.Unlock()
	records := make([]model.QuestionRecord, 0, len(qs))
	for _, q := range qs {
		id := db.nextQuestionID
		db.nextQuestionID++
		db.questions[id] = q
		records = append(records, model.QuestionRecord{ID: id, Description: q.Description, Answer: q.Answer})
	}
	return records, nil
}

func (_ *questionRepo) SearchQuestions(query string) ([]model.QuestionRecord, error) {
	needle := strings.ToLower(query)
	db.mu.RLock()
	defer db.mu.RUnlock()
	records := make([]model.QuestionRecord, 0, len(db.questions))
	for id, q := range db.questions {
		if needle == "" || strings.Contains(strings.ToLower(q.Description), needle) {
			records = append(records, model.QuestionRecord{ID: id, Description: q.Description, Answer: q.Answer})
		}
	}
	sort.Slice(records, func(i, j int) bool { return records[i].ID < records[j].ID })
	return records, nil
}

func (_ *questionRepo) UpdateQuestion(id uint, q model.Question) (bool, error) {
	db.mu.Lock()
	defer db.mu.Unlock()
	if _, ok := db.questions[id]; !ok {
		return false, nil
	}
	db.questions[id] = q
	return true, nil
}

func (_ *questionRepo) DeleteQuestion(id uint) (bool, error) {
	db.mu.Lock()
	defer db.mu.Unlock()
	if _, ok := db.questions[id]; !ok {
		return false, nil
	}
	delete(db.questions, id)
	return true, nil
}

func (_ *questionRepo) ConsumeSession(session string) (model.QuestionSession, bool, error) {
	db.mu.Lock()
	defer db.mu.Unlock()
	qs, ok := db.sessions[session]
	if ok {
		delete(db.sessions, session)
	}
	return qs, ok, nil
}

func InitQuestionRepo() QuestionRepo {
	return &questionRepo{}
}
