package repo

import (
	"context"
	crand "crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strconv"
	"time"

	"gb-api/internal/model"

	"github.com/jackc/pgx/v5"
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

// scanQuestion reads id + jsonb content/answer + difficulty/area into a record.
func scanQuestion(row pgx.Row) (model.QuestionRecord, error) {
	var (
		rec             model.QuestionRecord
		content, answer []byte
	)
	if err := row.Scan(&rec.ID, &content, &answer, &rec.Difficulty, &rec.Area); err != nil {
		return model.QuestionRecord{}, err
	}
	if err := json.Unmarshal(content, &rec.Content); err != nil {
		return model.QuestionRecord{}, err
	}
	if err := json.Unmarshal(answer, &rec.Answer); err != nil {
		return model.QuestionRecord{}, err
	}
	return rec, nil
}

// StoreSession assigns the session's TTL and a fresh id, then stores it.
func (_ *questionRepo) StoreSession(sess model.QuestionSession) (string, error) {
	ctx := context.Background()
	id, err := newSessionID()
	if err != nil {
		return "", err
	}
	sess.ExpiresAt = time.Now().Add(sessionTTL)
	data, err := json.Marshal(sess)
	if err != nil {
		return "", err
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO sessions (id, expires_at, data) VALUES ($1, $2, $3)`,
		id, sess.ExpiresAt, string(data),
	); err != nil {
		return "", err
	}
	return id, nil
}

// ConsumeSession atomically deletes and returns the (unexpired) session.
func (_ *questionRepo) ConsumeSession(session string) (model.QuestionSession, bool, error) {
	ctx := context.Background()
	var data []byte
	err := pool.QueryRow(ctx,
		`DELETE FROM sessions WHERE id = $1 AND expires_at > now() RETURNING data`, session,
	).Scan(&data)
	if errors.Is(err, pgx.ErrNoRows) {
		return model.QuestionSession{}, false, nil
	}
	if err != nil {
		return model.QuestionSession{}, false, err
	}
	var sess model.QuestionSession
	if err := json.Unmarshal(data, &sess); err != nil {
		return model.QuestionSession{}, false, err
	}
	return sess, true, nil
}

// RandomQuestion returns a random pool question (and its id) matching area, and
// difficulty when non-nil. ok is false when none match.
func (_ *questionRepo) RandomQuestion(area uint, difficulty *uint) (uint, model.Question, bool, error) {
	ctx := context.Background()
	sql := `SELECT id, content, answer, difficulty, area FROM questions WHERE area = $1`
	args := []any{area}
	if difficulty != nil {
		sql += ` AND difficulty = $2`
		args = append(args, *difficulty)
	}
	sql += ` ORDER BY random() LIMIT 1`
	rec, err := scanQuestion(pool.QueryRow(ctx, sql, args...))
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, model.Question{}, false, nil
	}
	if err != nil {
		return 0, model.Question{}, false, err
	}
	return rec.ID, recordToQuestion(rec), true, nil
}

func (_ *questionRepo) GetQuestion(id uint) (model.Question, bool, error) {
	ctx := context.Background()
	rec, err := scanQuestion(pool.QueryRow(ctx,
		`SELECT id, content, answer, difficulty, area FROM questions WHERE id = $1`, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return model.Question{}, false, nil
	}
	if err != nil {
		return model.Question{}, false, err
	}
	return recordToQuestion(rec), true, nil
}

func (_ *questionRepo) AddQuestions(qs []model.Question) ([]model.QuestionRecord, error) {
	ctx := context.Background()
	records := make([]model.QuestionRecord, 0, len(qs))
	for _, q := range qs {
		content, err := json.Marshal(q.Content)
		if err != nil {
			return nil, err
		}
		answer, err := json.Marshal(q.Answer)
		if err != nil {
			return nil, err
		}
		var id uint
		if err := pool.QueryRow(ctx,
			`INSERT INTO questions (content, answer, difficulty, area)
			 VALUES ($1, $2, $3, $4) RETURNING id`,
			string(content), string(answer), q.Difficulty, q.Area,
		).Scan(&id); err != nil {
			return nil, err
		}
		records = append(records, toRecord(id, q))
	}
	return records, nil
}

// SearchQuestions returns pool questions, optionally filtered by difficulty and area
// (each applied only when non-nil, as an exact match, AND-combined).
func (_ *questionRepo) SearchQuestions(difficulty, area *uint) ([]model.QuestionRecord, error) {
	ctx := context.Background()
	sql := `SELECT id, content, answer, difficulty, area FROM questions WHERE 1=1`
	var args []any
	if difficulty != nil {
		args = append(args, *difficulty)
		sql += ` AND difficulty = $` + strconv.Itoa(len(args))
	}
	if area != nil {
		args = append(args, *area)
		sql += ` AND area = $` + strconv.Itoa(len(args))
	}
	sql += ` ORDER BY id`
	rows, err := pool.Query(ctx, sql, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	records := make([]model.QuestionRecord, 0)
	for rows.Next() {
		rec, err := scanQuestion(rows)
		if err != nil {
			return nil, err
		}
		records = append(records, rec)
	}
	return records, rows.Err()
}

func (_ *questionRepo) UpdateQuestion(id uint, q model.Question) (bool, error) {
	ctx := context.Background()
	content, err := json.Marshal(q.Content)
	if err != nil {
		return false, err
	}
	answer, err := json.Marshal(q.Answer)
	if err != nil {
		return false, err
	}
	tag, err := pool.Exec(ctx,
		`UPDATE questions SET content = $2, answer = $3, difficulty = $4, area = $5 WHERE id = $1`,
		id, string(content), string(answer), q.Difficulty, q.Area,
	)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

func (_ *questionRepo) DeleteQuestion(id uint) (bool, error) {
	ctx := context.Background()
	tag, err := pool.Exec(ctx, `DELETE FROM questions WHERE id = $1`, id)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
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

// recordToQuestion is the inverse projection used where a model.Question is expected.
func recordToQuestion(rec model.QuestionRecord) model.Question {
	return model.Question{
		Content:    rec.Content,
		Answer:     rec.Answer,
		Difficulty: rec.Difficulty,
		Area:       rec.Area,
	}
}

func InitQuestionRepo() QuestionRepo {
	return &questionRepo{}
}
