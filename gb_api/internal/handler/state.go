package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sync"

	"gb-api/internal/model"
	"gb-api/internal/service"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
)

type StateHandler struct {
	svc   *service.StateSvc
	mu    sync.Mutex
	wg    sync.WaitGroup
	conns map[*websocket.Conn]struct{}
	down  bool
}

func NewStateHandler(s *service.StateSvc) *StateHandler {
	return &StateHandler{svc: s, conns: make(map[*websocket.Conn]struct{})}
}

// track registers a live WebSocket so Shutdown can close it. It returns false if
// the server is already shutting down, in which case the caller must not serve
// the connection.
func (h *StateHandler) track(conn *websocket.Conn) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.down {
		return false
	}
	h.conns[conn] = struct{}{}
	h.wg.Add(1)
	return true
}

func (h *StateHandler) untrack(conn *websocket.Conn) {
	h.mu.Lock()
	delete(h.conns, conn)
	h.mu.Unlock()
	h.wg.Done()
}

// Shutdown sends a Going-Away close frame to every live subscriber and waits for
// their handlers to return, or until ctx is cancelled. After it is called no new
// connections are served.
func (h *StateHandler) Shutdown(ctx context.Context) error {
	h.mu.Lock()
	h.down = true
	conns := make([]*websocket.Conn, 0, len(h.conns))
	for conn := range h.conns {
		conns = append(conns, conn)
	}
	h.mu.Unlock()

	// Close outside the lock since it does network I/O. Closing the connection
	// cancels the handler's read context, which unblocks its loop.
	for _, conn := range conns {
		conn.Close(websocket.StatusGoingAway, "server shutting down")
	}

	done := make(chan struct{})
	go func() { h.wg.Wait(); close(done) }()
	select {
	case <-done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (h *StateHandler) GetState(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	data, status, err := h.svc.GetState(token)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

func (h *StateHandler) SetState(w http.ResponseWriter, r *http.Request) {
	token, err := bearerToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	var req model.StateResponse
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "不合法的 JSON 格式", http.StatusBadRequest)
		return
	}
	if req.State == "" {
		http.Error(w, "缺少 state", http.StatusBadRequest)
		return
	}
	if _, exist := model.States[req.State]; !exist{
		http.Error(w, "不合法的狀態", http.StatusBadRequest)
		return
	}
	data, status, err := h.svc.SetState(token, req.State)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	writeJSON(w, data)
}

func wsAccessToken(r *http.Request) (string, error) {
	if t, err := bearerToken(r); err == nil {
		return t, nil
	}
	if t := r.URL.Query().Get("access_token"); t != "" {
		return t, nil
	}
	return "", fmt.Errorf("缺少 access token")
}

func (h *StateHandler) StateSocket(w http.ResponseWriter, r *http.Request) {
	token, err := wsAccessToken(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	cur, events, unsub, status, err := h.svc.SubscribeState(token)
	if err != nil {
		http.Error(w, err.Error(), status)
		return
	}
	defer unsub()

	conn, err := websocket.Accept(w, r, nil)
	if err != nil {
		return
	}
	defer conn.CloseNow()

	if !h.track(conn) {
		conn.Close(websocket.StatusGoingAway, "server shutting down")
		return
	}
	defer h.untrack(conn)

	ctx := conn.CloseRead(r.Context())

	if err := wsjson.Write(ctx, conn, cur); err != nil {
		return
	}
	for {
		select {
		case <-ctx.Done():
			return
		case s, ok := <-events:
			if !ok {
				return
			}
			if err := wsjson.Write(ctx, conn, s); err != nil {
				return
			}
		}
	}
}
