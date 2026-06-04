package model

import "time"

type Question struct {
	Description string
	Answer      uint
}

type QuestionSession struct {
	ExpiresAt time.Time
	GroupID   uint
	Question
}

type GenerateQuestionRequest struct {
	GroupID uint `json:"group_id"`
}

type QuestionResponse struct {
	Session     string `json:"session"`
	Description string `json:"description"`
}

type AnswerRequest struct {
	Session string `json:"session"`
	Answer  uint   `json:"answer"`
}

type AnswerResponse struct {
	Correct bool `json:"correct"`
}

// ServerState is the global quiz state machine. Students may only generate or
// answer questions while the server is in StateQuiz; teachers and admins always may.
type ServerState string

const (
	StateNormal ServerState = "NORMAL"
	StateQuiz   ServerState = "QUIZ"
)

type SetStateRequest struct {
	State ServerState `json:"state"`
}

type StateResponse struct {
	State ServerState `json:"state"`
}
