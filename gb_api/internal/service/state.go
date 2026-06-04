package service

import (
	"sync"

	"gb-api/internal/model"
)

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

func studentBlockedByState(role uint) bool {
	return role <= model.RoleStudent && getState() != model.StateQuiz
}
