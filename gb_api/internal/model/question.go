package model

import "time"

type Question struct {
	Description string
	Answer      uint
	Difficulty  uint
	Area        uint
}

// SessionKind distinguishes the two quiz flows a session can drive.
type SessionKind uint

const (
	KindItem   SessionKind = iota // answering correctly grants the new item
	KindTarget                    // answering correctly breaks/repairs a target slot
)

// Target identifies a group's slot for the QUIZ-state attack/repair flow.
type Target struct {
	GroupID uint
	SlotID  uint
}

type QuestionSession struct {
	ExpiresAt time.Time
	GroupID   uint
	Question  // embedded: the graded Description/Answer
	Kind      SessionKind
	ItemID    uint    // KindItem: the new item granted on a correct answer
	Target    *Target // KindTarget: the slot to break/repair
}

// GenerateItemRequest is the body of POST /api/question/generate (NORMAL state).
type GenerateItemRequest struct {
	Difficulty *uint `json:"difficulty"`
}

// GenerateTargetRequest is the body of POST /api/question/target (QUIZ state).
type GenerateTargetRequest struct {
	TargetGroupID *uint `json:"target_group_id"`
	TargetSlotID  *uint `json:"target_slot_id"`
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

// AnswerResponse reports the outcome of answering a session. ItemID is set when a
// KindItem answer grants an item; Success is set for KindTarget answers and reports
// whether the break/repair actually happened (false when the precondition no longer holds).
type AnswerResponse struct {
	Correct bool  `json:"correct"`
	ItemID  uint  `json:"item_id,omitempty"`
	Success *bool `json:"success,omitempty"`
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
