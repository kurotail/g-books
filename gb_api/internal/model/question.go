package model

import (
	"encoding/json"
	"time"
)

// Content type-value constants. A question's prompt (Description) may be plain
// text, an audio URL, or a voice_response prompt; its Choices are text-only for now.
const (
	DescText  = "text"
	DescAudio = "audio"
	DescVoice = "voice_response"

	ChoicesText  = "text"
	ChoicesAudio = "audio"

	AnswerIndex = "index"          // the answer is a zero-based index into Choices.Data
	AnswerVoice = "voice_response" // the answer is graded by transcribing submitted audio
)

// Description is a question prompt: Data is the text for DescText, or a URL for
// DescAudio / DescVoice.
type Description struct {
	Type string `json:"type"`
	Data string `json:"data"`
}

// Choices is the (optional) list of selectable options. Omitted for voice_response
// answers. Data holds option strings for ChoicesText, or audio URLs for ChoicesAudio.
type Choices struct {
	Type string   `json:"type"`
	Data []string `json:"data"`
}

// Content is the full question body handed to a student: a prompt plus, for
// multiple-choice questions, the choices. It never carries the answer.
type Content struct {
	Description Description `json:"description"`
	Choices     *Choices    `json:"choices,omitempty"` // nil for voice_response
}

// Answer is the typed correct answer. Data is a set:
// for AnswerIndex, an array of accepted zero-based choice indexes; for AnswerVoice, an
// array of accepted transcripts (compared case-insensitively to the STT output). The
// student submits a single value, which is graded correct if it matches any member.
type Answer struct {
	Type string          `json:"type"`
	Data json.RawMessage `json:"data"`
}

// IndexAnswer builds an AnswerIndex answer accepting any of the given zero-based
// choice indexes.
func IndexAnswer(idx ...uint) Answer {
	b, _ := json.Marshal(idx)
	return Answer{Type: AnswerIndex, Data: b}
}

// VoiceAnswer builds an AnswerVoice answer accepting any of the given transcripts.
func VoiceAnswer(text ...string) Answer {
	b, _ := json.Marshal(text)
	return Answer{Type: AnswerVoice, Data: b}
}

// TextContent builds a text-prompt, text-choices Content.
func TextContent(prompt string, choices ...string) Content {
	return Content{
		Description: Description{Type: DescText, Data: prompt},
		Choices:     &Choices{Type: ChoicesText, Data: choices},
	}
}

type Question struct {
	Content    Content
	Answer     Answer
	Difficulty uint
	Area       uint
}

// SessionKind distinguishes the two quiz flows a session can drive.
type SessionKind uint

const (
	KindItem   SessionKind = iota // answering correctly grants the new item
	KindTarget                    // answering correctly breaks/repairs a target slot
)

// Target identifies a user's slot for the QUIZ-state attack/repair flow.
type Target struct {
	UserID uint
	SlotID uint
}

type QuestionSession struct {
	ExpiresAt time.Time
	UserID    uint
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
	TargetUserID *uint `json:"target_user_id"`
	TargetSlotID *uint `json:"target_slot_id"`
}

// QuestionInput is a single question supplied by a teacher when uploading to or
// updating the pool. Content carries the prompt and (for multiple-choice) the
// choices; Answer is the typed correct answer.
type QuestionInput struct {
	Content    Content `json:"content"`
	Answer     Answer  `json:"answer"`
	Difficulty uint    `json:"difficulty"`
	Area       uint    `json:"area"`
}

// UploadQuestionsRequest is the body of POST /api/question/upload.
type UploadQuestionsRequest struct {
	Questions []QuestionInput `json:"questions"`
}

// QuestionRecord is a pool question as returned to teachers; unlike
// QuestionResponse it carries the id and the answer.
type QuestionRecord struct {
	ID         uint    `json:"id"`
	Content    Content `json:"content"`
	Answer     Answer  `json:"answer"`
	Difficulty uint    `json:"difficulty"`
	Area       uint    `json:"area"`
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
	Session string  `json:"session"`
	Content Content `json:"content"`
}

type AnswerRequest struct {
	Session string          `json:"session"`
	Answer  json.RawMessage `json:"answer"` // index question: a number; voice_response: an audio URL string
}

// TranscribeRequest carries a base64-encoded WAV recording for the standalone STT
// endpoint, mirroring the voice answer payload fed to STTRepo.Transcribe.
type TranscribeRequest struct {
	AudioB64 string `json:"audio_b64"`
}

// TranscribeResponse reports the text recognized from the submitted recording.
type TranscribeResponse struct {
	Text string `json:"text"`
}

// AnswerResponse reports the outcome of answering a session. ItemID is set when a
// KindItem answer grants an item; Success is set for KindTarget answers and reports
// whether the break/repair actually happened (false when the precondition no longer holds).
type AnswerResponse struct {
	Correct bool  `json:"correct"`
	ItemID  uint  `json:"item_id,omitempty"`
	Success *bool `json:"success,omitempty"`
}

// ServerState is the global quiz state machine, one of NORMAL / QUIZ1 / QUIZ2.
// Students may only generate items in NORMAL and only target (attack/repair) in QUIZ2;
// teachers and admins are never gated by the state.
type ServerState string

const (
	StateNormal ServerState = "NORMAL"
	StateQuiz1  ServerState = "QUIZ1"
	StateQuiz2  ServerState = "QUIZ2"
)

var States = map[ServerState]struct{}{
	StateNormal: {},
	StateQuiz1:  {},
	StateQuiz2:  {},
}

type StateResponse struct {
	State     ServerState `json:"state"`
	UpdatedAt time.Time   `json:"updated_at"`
	EndTime   *time.Time  `json:"end_time,omitempty"` // when state auto-reverts to NORMAL; nil = no schedule
}
