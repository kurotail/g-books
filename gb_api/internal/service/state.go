package service

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"

	"gb-api/internal/model"
	"gb-api/internal/repo"
)

// --- state machine ---

var (
	stateMu   sync.RWMutex
	state     = model.StateNormal
	updatedAt = time.Now() // when state last changed (server start for the initial NORMAL)
)

func getState() model.ServerState {
	stateMu.RLock()
	defer stateMu.RUnlock()
	return state
}

// stateSnapshot returns the current state and the time it last changed, read together
// under the lock so the pair is always consistent.
func stateSnapshot() model.StateResponse {
	stateMu.RLock()
	defer stateMu.RUnlock()
	return model.StateResponse{State: state, UpdatedAt: updatedAt}
}

func setState(s model.ServerState) {
	stateMu.Lock()
	changed := state != s
	if changed {
		state = s
		updatedAt = time.Now()
	}
	snap := model.StateResponse{State: state, UpdatedAt: updatedAt}
	stateMu.Unlock()
	// Only a real transition (between NORMAL / QUIZ1 / QUIZ2) is worth notifying about.
	if changed {
		stateHub.broadcast(snap)
	}
}

// --- broadcast hub ---

var stateHub = &hub{subs: make(map[chan model.StateResponse]struct{})}

type hub struct {
	mu   sync.Mutex
	subs map[chan model.StateResponse]struct{}
}

func (h *hub) subscribe() (<-chan model.StateResponse, func()) {
	ch := make(chan model.StateResponse, 8)
	h.mu.Lock()
	h.subs[ch] = struct{}{}
	h.mu.Unlock()

	unsub := func() {
		h.mu.Lock()
		if _, ok := h.subs[ch]; ok {
			delete(h.subs, ch)
			close(ch)
		}
		h.mu.Unlock()
	}
	return ch, unsub
}

func (h *hub) broadcast(s model.StateResponse) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for ch := range h.subs {
		select {
		case ch <- s:
		default:
		}
	}
}

// --- service ---

type StateSvc struct {
	users repo.UserRepo
}

func NewStateSvc(users repo.UserRepo) *StateSvc {
	return &StateSvc{users: users}
}

func (s *StateSvc) GetState(accessToken string) ([]byte, int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return nil, http.StatusUnauthorized, err
	}
	data, err := json.Marshal(stateSnapshot())
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func (s *StateSvc) SetState(accessToken string, state model.ServerState) ([]byte, int, error) {
	if status, err := requireTeacher(s.users, accessToken); err != nil {
		return nil, status, err
	}
	if _, ok := model.States[state]; !ok {
		return nil, http.StatusBadRequest, fmt.Errorf("不合法的狀態: %q", state)
	}
	setState(state)
	data, err := json.Marshal(stateSnapshot())
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return data, http.StatusOK, nil
}

func (s *StateSvc) SubscribeState(accessToken string) (model.StateResponse, <-chan model.StateResponse, func(), int, error) {
	if _, err := validateAccessToken(accessToken); err != nil {
		return model.StateResponse{}, nil, nil, http.StatusUnauthorized, err
	}
	events, unsub := stateHub.subscribe()
	return stateSnapshot(), events, unsub, http.StatusOK, nil
}
