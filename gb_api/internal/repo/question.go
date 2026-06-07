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
	CreateSession(groupID uint) (string, model.Question, error)
	ConsumeSession(session string) (model.QuestionSession, bool, error)
	AddQuestions(qs []model.Question) ([]model.QuestionRecord, error)
	SearchQuestions(query string, difficulty, area *uint) ([]model.QuestionRecord, error)
	UpdateQuestion(id uint, q model.Question) (bool, error)
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
		records = append(records, toRecord(id, q))
	}
	return records, nil
}

// SearchQuestions returns pool questions matching the description substring (empty
// matches all). The difficulty and area filters are applied only when non-nil, each
// as an exact match, AND-combined with the substring.
func (_ *questionRepo) SearchQuestions(query string, difficulty, area *uint) ([]model.QuestionRecord, error) {
	needle := strings.ToLower(query)
	db.mu.RLock()
	defer db.mu.RUnlock()
	records := make([]model.QuestionRecord, 0, len(db.questions))
	for id, q := range db.questions {
		if needle != "" && !strings.Contains(strings.ToLower(q.Description), needle) {
			continue
		}
		if difficulty != nil && q.Difficulty != *difficulty {
			continue
		}
		if area != nil && q.Area != *area {
			continue
		}
		records = append(records, toRecord(id, q))
	}
	sort.Slice(records, func(i, j int) bool { return records[i].ID < records[j].ID })
	return records, nil
}

// toRecord maps a stored question to its teacher-facing record.
func toRecord(id uint, q model.Question) model.QuestionRecord {
	return model.QuestionRecord{
		ID:          id,
		Description: q.Description,
		Answer:      q.Answer,
		Difficulty:  q.Difficulty,
		Area:        q.Area,
	}
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
