// tart the server (go run ./cmd/server) and then run
// `go run ./cmd/smoke` to fire real HTTP requests at every route and print the
// status code + response body so the behavior can be eyeballed.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
)

const base = "http://localhost:8080"
const wsBase = "ws://localhost:8080"

var client = &http.Client{Timeout: 5 * time.Second}

var checks, fails int

// req sends Method Path with an optional bearer token and JSON body, returning
// the status code and trimmed response body. Never panics on HTTP errors.
func req(method, path, token string, body any) (int, string) {
	var rdr io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rdr = bytes.NewReader(b)
	}
	r, err := http.NewRequest(method, base+path, rdr)
	if err != nil {
		return -1, err.Error()
	}
	if body != nil {
		r.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		r.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := client.Do(r)
	if err != nil {
		return -1, err.Error()
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, strings.TrimSpace(string(b))
}

// show prints one check, comparing the actual status against what we expect.
func show(title string, status int, want int, body string) {
	checks++
	mark := "OK"
	if status != want {
		mark = "XX"
		fails++
	}
	fmt.Printf("[%s] %-46s -> %d (want %d)\n", mark, title, status, want)
	if body != "" {
		fmt.Printf("       %s\n", body)
	}
}

// tokens pulls access_token / refresh_token out of a login/refresh body.
func tokens(body string) (access, refresh string) {
	var t struct {
		Access  string `json:"access_token"`
		Refresh string `json:"refresh_token"`
	}
	json.Unmarshal([]byte(body), &t)
	return t.Access, t.Refresh
}

func section(name string) { fmt.Printf("\n=== %s ===\n", name) }

// stateEvent mirrors the JSON pushed over the state WebSocket.
type stateEvent struct {
	State string `json:"state"`
}

// readEvent reads one JSON frame with a short deadline.
func readEvent(conn *websocket.Conn) (stateEvent, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	var ev stateEvent
	err := wsjson.Read(ctx, conn, &ev)
	return ev, err
}

// wsChecks exercises the /api/state/ws endpoint: header auth, the on-connect
// snapshot, live QUIZ2/NORMAL transitions, query-param auth, and rejection of
// unauthenticated dials.
func wsChecks(access, sAccess string) {
	// Unauthenticated dial must be rejected before the upgrade (HTTP 401).
	dctx, dcancel := context.WithTimeout(context.Background(), 3*time.Second)
	_, resp, err := websocket.Dial(dctx, wsBase+"/api/state/ws", nil)
	dcancel()
	gotStatus := -1
	if resp != nil {
		gotStatus = resp.StatusCode
	}
	checks++
	if err != nil && gotStatus == http.StatusUnauthorized {
		fmt.Printf("[OK] %-46s -> %d (want 401)\n", "ws dial without token rejected", gotStatus)
	} else {
		fails++
		fmt.Printf("[XX] %-46s -> %d (want 401, err=%v)\n", "ws dial without token rejected", gotStatus, err)
	}

	// Authenticated dial via Authorization header.
	dctx, dcancel = context.WithTimeout(context.Background(), 3*time.Second)
	conn, _, err := websocket.Dial(dctx, wsBase+"/api/state/ws", &websocket.DialOptions{
		HTTPHeader: http.Header{"Authorization": {"Bearer " + access}},
	})
	dcancel()
	if err != nil {
		checks++
		fails++
		fmt.Printf("[XX] %-46s -> err=%v\n", "ws dial with header token", err)
		return
	}
	defer conn.Close(websocket.StatusNormalClosure, "")

	// On-connect snapshot (state was left at NORMAL by the prior section).
	ev, err := readEvent(conn)
	showWS("ws snapshot on connect (NORMAL)", ev, err, "NORMAL")

	// Flip to QUIZ2 via REST and expect a pushed event.
	st, _ := req("POST", "/api/state", access, map[string]any{"state": "QUIZ2"})
	show("set state QUIZ2 (to trigger ws)", st, 200, "")
	ev, err = readEvent(conn)
	showWS("ws receives QUIZ2 transition", ev, err, "QUIZ2")

	// Flip back to NORMAL and expect another event.
	st, _ = req("POST", "/api/state", access, map[string]any{"state": "NORMAL"})
	show("set state NORMAL (to trigger ws)", st, 200, "")
	ev, err = readEvent(conn)
	showWS("ws receives NORMAL transition", ev, err, "NORMAL")

	// A non-teacher token may still subscribe (same policy as GET /api/state),
	// this time authenticating via the ?access_token= query fallback.
	dctx, dcancel = context.WithTimeout(context.Background(), 3*time.Second)
	sConn, _, err := websocket.Dial(dctx, wsBase+"/api/state/ws?access_token="+sAccess, nil)
	dcancel()
	if err != nil {
		checks++
		fails++
		fmt.Printf("[XX] %-46s -> err=%v\n", "ws dial with query-param token", err)
		return
	}
	defer sConn.Close(websocket.StatusNormalClosure, "")
	ev, err = readEvent(sConn)
	showWS("ws query-param auth snapshot", ev, err, "NORMAL")
}

// showWS prints one WebSocket check comparing the received event to expectations.
func showWS(title string, ev stateEvent, err error, wantState string) {
	checks++
	if err == nil && ev.State == wantState {
		fmt.Printf("[OK] %-46s -> {state:%s}\n", title, ev.State)
		return
	}
	fails++
	fmt.Printf("[XX] %-46s -> {state:%s} (want {state:%s} err=%v)\n",
		title, ev.State, wantState, err)
}

// allReceived reads one frame from every connection and reports whether they
// all carry wantState. It always drains every conn (no early return) so a single
// slow/wrong subscriber does not leave the others' frames unread.
func allReceived(conns []*websocket.Conn, wantState string) bool {
	ok := true
	for i, c := range conns {
		ev, err := readEvent(c)
		if err != nil || ev.State != wantState {
			ok = false
			fmt.Printf("       subscriber %d: got {state:%s} err=%v\n", i, ev.State, err)
		}
	}
	return ok
}

// wsFanout opens many student subscribers on /api/state/ws and verifies that a
// single teacher-driven transition is broadcast to every one of them. All
// subscribers share one student token — the endpoint authorizes any user, and a
// token may back any number of independent connections.
func wsFanout(access, sAccess string) {
	const n = 10

	// Establish a known NORMAL baseline before anyone subscribes, so every
	// snapshot is NORMAL and the later flip to QUIZ2 is a real transition.
	req("POST", "/api/state", access, map[string]any{"state": "NORMAL"})

	conns := make([]*websocket.Conn, 0, n)
	defer func() {
		for _, c := range conns {
			c.Close(websocket.StatusNormalClosure, "")
		}
	}()

	snapOK := true
	for i := range n {
		dctx, dcancel := context.WithTimeout(context.Background(), 3*time.Second)
		c, _, err := websocket.Dial(dctx, wsBase+"/api/state/ws?access_token="+sAccess, nil)
		dcancel()
		if err != nil {
			snapOK = false
			fmt.Printf("       student %d dial err: %v\n", i, err)
			break
		}
		conns = append(conns, c)
		if ev, err := readEvent(c); err != nil || ev.State != "NORMAL" {
			snapOK = false
		}
	}
	checks++
	if snapOK && len(conns) == n {
		fmt.Printf("[OK] %-46s -> %d connected, all NORMAL snapshot\n", "fanout: students subscribe", n)
	} else {
		fails++
		fmt.Printf("[XX] %-46s -> %d/%d connected ok=%v\n", "fanout: students subscribe", len(conns), n, snapOK)
	}

	// One teacher transition must reach every subscriber.
	st, _ := req("POST", "/api/state", access, map[string]any{"state": "QUIZ2"})
	show("fanout: teacher sets QUIZ2", st, 200, "")
	checks++
	if allReceived(conns, "QUIZ2") {
		fmt.Printf("[OK] %-46s -> all %d received QUIZ2\n", "fanout: every subscriber notified", len(conns))
	} else {
		fails++
		fmt.Printf("[XX] %-46s -> not all %d received QUIZ2\n", "fanout: every subscriber notified", len(conns))
	}

	// And again on the way back to NORMAL.
	st, _ = req("POST", "/api/state", access, map[string]any{"state": "NORMAL"})
	show("fanout: teacher sets NORMAL", st, 200, "")
	checks++
	if allReceived(conns, "NORMAL") {
		fmt.Printf("[OK] %-46s -> all %d received NORMAL\n", "fanout: every subscriber notified", len(conns))
	} else {
		fails++
		fmt.Printf("[XX] %-46s -> not all %d received NORMAL\n", "fanout: every subscriber notified", len(conns))
	}
}

func main() {
	section("AUTH")

	st, _ := req("POST", "/api/login", "", map[string]any{"username": "user", "password": "wrongpass"})
	show("login with wrong password", st, 401, "")

	st, body := req("POST", "/api/login", "", map[string]any{"username": "user", "password": "password123"})
	show("login as seeded teacher (user)", st, 200, body)
	access, refresh := tokens(body)
	if access == "" {
		fmt.Println("\nFATAL: could not obtain access token; is the server running on :8080?")
		os.Exit(1)
	}

	st, _ = req("GET", "/api/users", "", nil)
	show("GET /api/users without token", st, 401, "")

	st, body = req("GET", "/api/users", access, nil)
	show("GET /api/users with token", st, 200, body)

	section("REGISTER (teacher-only)")

	st, _ = req("POST", "/api/register", access, map[string]any{"username": "stud1", "password": "pw", "role": 0, "group_id": 2})
	show("teacher registers a student into group 2", st, 201, "")

	st, body = req("POST", "/api/register", access, map[string]any{"username": "stud1", "password": "pw", "role": 0})
	show("register duplicate username", st, 409, body)

	st, body = req("POST", "/api/register", access, map[string]any{"username": "admin1", "password": "pw", "role": 2})
	show("teacher tries to create admin (role 2)", st, 403, body)

	st, body = req("POST", "/api/register", access, map[string]any{"username": "noRole", "password": "pw"})
	show("register missing role", st, 400, body)

	st, body = req("POST", "/api/login", "", map[string]any{"username": "stud1", "password": "pw"})
	show("login as new student stud1", st, 200, body)
	sAccess, _ := tokens(body)

	st, body = req("POST", "/api/register", sAccess, map[string]any{"username": "x", "password": "pw", "role": 0})
	show("student tries to register (forbidden)", st, 403, body)

	section("GROUPS")

	st, body = req("GET", "/api/group", access, nil)
	show("teacher queries own group", st, 200, body)

	st, _ = req("POST", "/api/group/set", access, map[string]any{"username": "stud1", "group_id": 1})
	show("teacher adds stud1 to group 1", st, 200, "")

	st, body = req("GET", "/api/group", access, nil)
	show("query own group (members now include stud1)", st, 200, body)

	st, _ = req("POST", "/api/group/set", access, map[string]any{"username": "stud1", "group_id": 0})
	show("teacher removes stud1 from group (group_id 0)", st, 200, "")

	st, body = req("POST", "/api/item", access, map[string]any{"group_id": 0})
	show("query items of group 0 (rejected, must be > 0)", st, 400, body)

	st, body = req("POST", "/api/group/set", sAccess, map[string]any{"username": "stud1", "group_id": 1})
	show("student tries to set group (forbidden)", st, 403, body)

	section("ITEMS")

	// Assign building 1 to group 1 so the Type-allowed-slot rule applies
	// (building 1 allows type 10 in slots 0,1 and type 20 in slot 2).
	st, _ = req("POST", "/api/group/building", access, map[string]any{"group_id": 1, "building_id": 1})
	show("assign building 1 to group 1", st, 200, "")

	st, body = req("POST", "/api/item", access, map[string]any{"group_id": 1})
	show("query items of group 1 (inventory + slots)", st, 200, body)

	st, body = req("POST", "/api/item/inv2slot", access, map[string]any{"group_id": 1, "item_id": 0, "slot_id": 1})
	show("inv2slot with item_id 0 (rejected)", st, 400, body)

	st, _ = req("POST", "/api/item/inv2slot", access, map[string]any{"group_id": 1, "item_id": 1, "slot_id": 1})
	show("move item 1 (type 10) into allowed slot 1", st, 200, "")

	st, body = req("POST", "/api/item", access, map[string]any{"group_id": 1})
	show("items after inv2slot", st, 200, body)

	st, body = req("POST", "/api/item/inv2slot", access, map[string]any{"group_id": 1, "item_id": 2, "slot_id": 1})
	show("move item 2 (type 20) into slot 1 (type not allowed)", st, 400, body)

	st, body = req("POST", "/api/item/inv2slot", access, map[string]any{"group_id": 1, "item_id": 99, "slot_id": 1})
	show("move item not in inventory (rejected)", st, 400, body)

	st, body = req("POST", "/api/item/slot2inv", access, map[string]any{"group_id": 1, "slot_id": 1})
	show("move slot 1 back to inventory", st, 200, body)

	st, body = req("POST", "/api/item", access, map[string]any{"group_id": 1})
	show("items after slot2inv (item 1 restored)", st, 200, body)

	st, body = req("POST", "/api/item/inv2slot", access, map[string]any{"group_id": 1})
	show("inv2slot missing item_id/slot_id", st, 400, body)

	section("STATE + QUESTIONS")

	st, body = req("GET", "/api/state", access, nil)
	show("get state (default)", st, 200, body)

	st, body = req("POST", "/api/state", access, map[string]any{"state": "QUIZ2"})
	show("teacher sets state QUIZ2", st, 200, body)

	st, body = req("POST", "/api/state", sAccess, map[string]any{"state": "NORMAL"})
	show("student tries to set state (forbidden)", st, 403, body)

	st, body = req("POST", "/api/state", access, map[string]any{"state": "BOGUS"})
	show("set invalid state value", st, 400, body)

	var q struct {
		Session string `json:"session"`
	}

	// --- item flow (NORMAL): generate a new item, answer correctly to earn it ---
	st, _ = req("POST", "/api/state", access, map[string]any{"state": "NORMAL"})
	show("teacher sets state NORMAL", st, 200, "")

	st, body = req("POST", "/api/question/generate", access, map[string]any{"difficulty": 1})
	show("teacher generates an item (difficulty 1)", st, 200, body)
	json.Unmarshal([]byte(body), &q)

	st, body = req("POST", "/api/question/answer", access, map[string]any{"session": q.Session, "answer": 1})
	show("answer correctly -> item granted (item_id)", st, 200, body)

	st, body = req("POST", "/api/question/answer", access, map[string]any{"session": q.Session, "answer": 1})
	show("answer same session again (consumed)", st, 400, body)

	st, body = req("POST", "/api/question/answer", access, map[string]any{"answer": 0})
	show("answer missing session", st, 400, body)

	st, body = req("POST", "/api/question/generate", access, map[string]any{"difficulty": 9})
	show("generate item for a difficulty with no type (rejected)", st, 400, body)

	// --- fetch a single question by id (any authenticated user) ---
	st, body = req("GET", "/api/question/1", access, nil)
	show("get question 1 by id (record incl. answer)", st, 200, body)

	st, body = req("GET", "/api/question/9999", access, nil)
	show("get unknown question id (404)", st, 404, body)

	// --- attack/repair flow (QUIZ2) ---
	st, _ = req("POST", "/api/register", access, map[string]any{"username": "quizzer", "password": "pw", "role": 0, "group_id": 2})
	show("register attacker quizzer in group 2", st, 201, "")
	_, body = req("POST", "/api/login", "", map[string]any{"username": "quizzer", "password": "pw"})
	qAccess, _ := tokens(body)

	st, _ = req("POST", "/api/state", access, map[string]any{"state": "QUIZ2"})
	show("teacher sets state QUIZ2", st, 200, "")

	// group-2 student attacks group-1 slot 0 (item 3, normal, carries a question)
	st, body = req("POST", "/api/question/target", qAccess, map[string]any{"target_group_id": 1, "target_slot_id": 0})
	show("group-2 student targets group-1 slot 0 (attack)", st, 200, body)
	json.Unmarshal([]byte(body), &q)
	st, body = req("POST", "/api/question/answer", qAccess, map[string]any{"session": q.Session, "answer": 1})
	show("answer correctly -> break the item (success)", st, 200, body)

	st, body = req("POST", "/api/item", access, map[string]any{"group_id": 1})
	show("group 1 items (slot 0 now broken)", st, 200, body)

	// teacher repairs their own now-broken slot (repair question is area 2, answer 0)
	st, body = req("POST", "/api/question/target", access, map[string]any{"target_group_id": 1, "target_slot_id": 0})
	show("teacher targets own broken slot (repair)", st, 200, body)
	json.Unmarshal([]byte(body), &q)
	st, body = req("POST", "/api/question/answer", access, map[string]any{"session": q.Session, "answer": 0})
	show("answer correctly -> repair the item (success)", st, 200, body)

	st, body = req("POST", "/api/question/target", access, map[string]any{"target_group_id": 1, "target_slot_id": 0})
	show("target own non-broken slot (invalid)", st, 400, body)

	st, body = req("POST", "/api/question/generate", qAccess, map[string]any{"difficulty": 1})
	show("student generates item in QUIZ2 (blocked)", st, 403, body)

	st, _ = req("POST", "/api/state", access, map[string]any{"state": "NORMAL"})
	show("teacher sets state NORMAL", st, 200, "")

	section("STATE WEBSOCKET")
	wsChecks(access, sAccess)

	section("STATE WS FANOUT")
	wsFanout(access, sAccess)

	section("REFRESH")

	st, body = req("POST", "/api/refresh", "", map[string]any{"refresh_token": refresh})
	show("refresh with valid refresh token", st, 200, body)

	st, body = req("POST", "/api/refresh", "", map[string]any{"refresh_token": refresh})
	show("reuse consumed refresh token", st, 401, body)

	st, body = req("POST", "/api/refresh", "", map[string]any{"refresh_token": "garbage"})
	show("refresh with garbage token", st, 401, body)

	section("AUTH EDGES")

	st, body = req("GET", "/api/users", "not.a.jwt", nil)
	show("request with malformed bearer token", st, 401, body)

	fmt.Printf("\nDone. %d checks, %d mismatches.\n", checks, fails)
	if fails > 0 {
		os.Exit(1)
	}
}
