package repo

import (
	crand "crypto/rand"
	"encoding/hex"
	mrand "math/rand"
	"sync"
	"time"

	"gb-api/internal/model"
)

const sessionTTL = 15 * time.Minute

var questionMu sync.Mutex

type QuestionRepo interface {
	// CreateSession picks a random question, stores a single-use session for it,
	// and returns the session ID together with the picked question.
	CreateSession(groupID uint) (string, model.Question, error)
	// ConsumeSession loads and deletes a session. ok is false when absent.
	ConsumeSession(session string) (model.QuestionSession, bool, error)
	// GetRole returns a user's role level; unknown users default to
	// RoleStudent (0).
	GetRole(username string) (uint, error)
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
	q := questionList[mrand.Intn(len(questionList))]
	id, err := newSessionID()
	if err != nil {
		return "", model.Question{}, err
	}
	questionMu.Lock()
	defer questionMu.Unlock()
	mem_db.questions[id] = model.QuestionSession{
		ExpiresAt: time.Now().Add(sessionTTL),
		GroupID:   groupID,
		Question:  q,
	}
	return id, q, nil
}

func (_ *questionRepo) ConsumeSession(session string) (model.QuestionSession, bool, error) {
	questionMu.Lock()
	defer questionMu.Unlock()
	qs, ok := mem_db.questions[session]
	if ok {
		delete(mem_db.questions, session)
	}
	return qs, ok, nil
}

func (_ *questionRepo) GetRole(username string) (uint, error) {
	return mem_db.roles[username], nil
}

func InitQuestionRepo() QuestionRepo {
	return &questionRepo{}
}
