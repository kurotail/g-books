package repo

import (
	crand "crypto/rand"
	"encoding/hex"
	mrand "math/rand"
	"sort"
	"time"

	"gb-api/internal/model"
)

const sessionTTL = 15 * time.Minute

type QuestionRepo interface {
	StoreSession(sess model.QuestionSession) (string, error)
	ConsumeSession(session string) (model.QuestionSession, bool, error)
	RandomQuestion(area uint, difficulty *uint) (uint, model.Question, bool, error)
	GetQuestion(id uint) (model.Question, bool, error)
	AddQuestions(qs []model.Question) ([]model.QuestionRecord, error)
	SearchQuestions(difficulty, area *uint) ([]model.QuestionRecord, error)
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

// StoreSession assigns the session's TTL and a fresh id, then stores it.
func (_ *questionRepo) StoreSession(sess model.QuestionSession) (string, error) {
	id, err := newSessionID()
	if err != nil {
		return "", err
	}
	sess.ExpiresAt = time.Now().Add(sessionTTL)
	db.mu.Lock()
	defer db.mu.Unlock()
	db.sessions[id] = sess
	return id, nil
}

// RandomQuestion returns a random pool question (and its id) matching area, and
// difficulty when non-nil. ok is false when none match.
func (_ *questionRepo) RandomQuestion(area uint, difficulty *uint) (uint, model.Question, bool, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	type entry struct {
		id uint
		q  model.Question
	}
	var matches []entry
	for id, q := range db.questions {
		if q.Area != area {
			continue
		}
		if difficulty != nil && q.Difficulty != *difficulty {
			continue
		}
		matches = append(matches, entry{id, q})
	}
	if len(matches) == 0 {
		return 0, model.Question{}, false, nil
	}
	pick := matches[mrand.Intn(len(matches))]
	return pick.id, pick.q, true, nil
}

func (_ *questionRepo) GetQuestion(id uint) (model.Question, bool, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	q, ok := db.questions[id]
	return q, ok, nil
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

// SearchQuestions returns pool questions, optionally filtered by difficulty and area
// (each applied only when non-nil, as an exact match, AND-combined).
func (_ *questionRepo) SearchQuestions(difficulty, area *uint) ([]model.QuestionRecord, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	records := make([]model.QuestionRecord, 0, len(db.questions))
	for id, q := range db.questions {
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
		ID:         id,
		Content:    q.Content,
		Answer:     q.Answer,
		Difficulty: q.Difficulty,
		Area:       q.Area,
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
