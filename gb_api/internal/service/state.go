package service

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"

	"gb-api/internal/logger"
	"gb-api/internal/model"
	"gb-api/internal/repo"
)

// --- state machine ---

var (
	stateMu   sync.RWMutex
	state     = model.StateNormal
	updatedAt = time.Now()  // when state last changed (server start for the initial NORMAL)
	endTime   = time.Time{} // when the state auto-reverts to NORMAL; zero = no schedule
)

func getState() model.ServerState {
	stateMu.RLock()
	defer stateMu.RUnlock()
	return state
}

// snapshotLocked builds the current state response. Callers must hold stateMu.
func snapshotLocked() model.StateResponse {
	resp := model.StateResponse{State: state, UpdatedAt: updatedAt}
	if !endTime.IsZero() {
		e := endTime
		resp.EndTime = &e
	}
	return resp
}

// stateSnapshot returns the current state, the time it last changed, and any
// scheduled end time, read together under the lock so they are always consistent.
func stateSnapshot() model.StateResponse {
	stateMu.RLock()
	defer stateMu.RUnlock()
	return snapshotLocked()
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
	users  repo.UserRepo
	blocks repo.BlockRepo
}

func NewStateSvc(users repo.UserRepo, blocks repo.BlockRepo) *StateSvc {
	return &StateSvc{users: users, blocks: blocks}
}

// clearAttackBlocks wipes every slot's attacker block list
func (s *StateSvc) clearAttackBlocks() {
	if err := s.blocks.ClearAllAttackBlocks(); err != nil {
		logger.L.Error("failed to clear slot attack blocks on NORMAL", "err", err)
	}
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

// SetState transitions the global state. Teachers/admins only.
func (s *StateSvc) SetState(accessToken string, st model.ServerState, endTime *time.Time) ([]byte, int, error) {
	if status, err := requireTeacher(s.users, accessToken); err != nil {
		return nil, status, err
	}
	if _, ok := model.States[st]; !ok {
		return nil, http.StatusBadRequest, fmt.Errorf("不合法的狀態: %q", st)
	}
	var end time.Time
	if endTime != nil && st != model.StateNormal {
		if !endTime.After(time.Now()) {
			return nil, http.StatusBadRequest, fmt.Errorf("end_time 必須是未來時間")
		}
		end = *endTime
	}
	s.setStateUntil(st, end)
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

func (s *StateSvc) setStateUntil(ns model.ServerState, end time.Time) {
	stateMu.Lock()
	changed := state != ns
	endChanged := !endTime.Equal(end)
	if changed {
		state = ns
		updatedAt = time.Now()
	}
	endTime = end
	snap := snapshotLocked()
	stateMu.Unlock()
	// Returning to NORMAL clears every per-slot attack block.
	if ns == model.StateNormal {
		s.clearAttackBlocks()
	}
	// Notify on a real transition or a (re)scheduled end time.
	if changed || endChanged {
		stateHub.broadcast(snap)
	}
}

// revertIfDue transitions to NORMAL and clears the schedule when the end time
func (s *StateSvc) revertIfDue(now time.Time) {
	stateMu.Lock()
	defer stateMu.Unlock()
	if endTime.IsZero() || now.Before(endTime) {
		stateMu.Unlock()
		return
	}
	reverted := state != model.StateNormal
	if reverted {
		state = model.StateNormal
		updatedAt = time.Now()
		s.clearAttackBlocks()
	}
	endTime = time.Time{}
	snap := snapshotLocked()
	stateHub.broadcast(snap)
}

func (s *StateSvc) StartStateScheduler(ctx context.Context, interval time.Duration) {
	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case t := <-ticker.C:
				s.revertIfDue(t)
			}
		}
	}()
}
