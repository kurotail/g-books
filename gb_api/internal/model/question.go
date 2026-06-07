package model

import "time"

type Question struct {
	Description string
	Answer      uint
	Difficulty  uint
	Area        uint
}

type QuestionSession struct {
	ExpiresAt time.Time
	GroupID   uint
	Question
}

type GenerateQuestionRequest struct {
	GroupID *uint `json:"group_id"`
}

// QuestionInput is a single question supplied by a teacher when uploading to or
// updating the pool. Answer is the index of the correct choice; the choices are
// embedded as text inside Description.
type QuestionInput struct {
	Description string `json:"description"`
	Answer      uint   `json:"answer"`
	Difficulty  uint   `json:"difficulty"`
	Area        uint   `json:"area"`
}

// UploadQuestionsRequest is the body of POST /api/question/upload.
type UploadQuestionsRequest struct {
	Questions []QuestionInput `json:"questions"`
}

// QuestionRecord is a pool question as returned to teachers; unlike
// QuestionResponse it carries the id and the answer.
type QuestionRecord struct {
	ID          uint   `json:"id"`
	Description string `json:"description"`
	Answer      uint   `json:"answer"`
	Difficulty  uint   `json:"difficulty"`
	Area        uint   `json:"area"`
}

// QuestionListResponse is returned by the search endpoint.
type QuestionListResponse struct {
	Questions []QuestionRecord `json:"questions"`
}

// QuestionUploadResult is the outcome of a single question in a bulk upload.
// Status is the per-question HTTP status (201 created, 400 invalid); ID is set
// only when created, Error only when rejected.
type QuestionUploadResult struct {
	Index  int    `json:"index"`
	Status int    `json:"status"`
	ID     uint   `json:"id,omitempty"`
	Error  string `json:"error,omitempty"`
}

// UploadQuestionsResponse is the 207 Multi-Status body for a bulk upload: one
// result per submitted question, in request order.
type UploadQuestionsResponse struct {
	Results []QuestionUploadResult `json:"results"`
}

type QuestionResponse struct {
	Session     string `json:"session"`
	Description string `json:"description"`
}

type AnswerRequest struct {
	Session string `json:"session"`
	Answer  *uint  `json:"answer"`
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
