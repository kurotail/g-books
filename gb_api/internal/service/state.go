package service

import (
	"sync"

	"gb-api/internal/model"
)

// state is the global quiz state machine, maintained in-process by the service
// layer. Students may only generate or answer questions while it is StateQuiz;
// teachers and admins are unaffected.
var (
	stateMu sync.RWMutex
	state   = model.StateNormal
)

func getState() model.ServerState {
	stateMu.RLock()
	defer stateMu.RUnlock()
	return state
}

func setState(s model.ServerState) {
	stateMu.Lock()
	defer stateMu.Unlock()
	state = s
}

// studentBlockedByState reports whether a caller of the given permission is
// barred from question operations by the current state (students outside QUIZ).
func studentBlockedByState(perm uint) bool {
	return perm <= model.PermStudent && getState() != model.StateQuiz
}
