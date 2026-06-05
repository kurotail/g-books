// tart the server (go run ./cmd/server) and then run
// `go run ./cmd/smoke` to fire real HTTP requests at every route and print the
// status code + response body so the behavior can be eyeballed.
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

const base = "http://localhost:8080"

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

	st, _ = req("POST", "/api/register", access, map[string]any{"username": "stud1", "password": "pw", "role": 0})
	show("teacher registers a student", st, 201, "")

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

	st, _ = req("POST", "/api/group/set", access, map[string]any{"username": "stud1", "group_id": 0})
	show("teacher adds stud1 to group 0", st, 200, "")

	st, body = req("POST", "/api/group/members", access, map[string]any{"group_id": 0})
	show("query members of group 0", st, 200, body)

	st, body = req("POST", "/api/group/set", sAccess, map[string]any{"username": "stud1", "group_id": 1})
	show("student tries to set group (forbidden)", st, 403, body)

	section("ITEMS")

	st, body = req("POST", "/api/item/inv", access, map[string]any{"group_id": 0})
	show("query inventory of group 0", st, 200, body)

	st, body = req("POST", "/api/item/slot", access, map[string]any{"group_id": 0})
	show("query slots of group 0", st, 200, body)

	st, body = req("POST", "/api/item/inv2slot", access, map[string]any{"group_id": 0, "item_id": 0, "slot_id": 9})
	show("inv2slot with item_id 0 (rejected)", st, 400, body)

	st, _ = req("POST", "/api/item/inv2slot", access, map[string]any{"group_id": 0, "item_id": 1, "slot_id": 9})
	show("move item 1 from inv to slot 9", st, 200, "")

	st, body = req("POST", "/api/item/inv", access, map[string]any{"group_id": 0})
	show("inventory after inv2slot", st, 200, body)

	st, body = req("POST", "/api/item/inv2slot", access, map[string]any{"group_id": 0, "item_id": 99, "slot_id": 8})
	show("move nonexistent item (insufficient)", st, 400, body)

	st, body = req("POST", "/api/item/slot2inv", access, map[string]any{"group_id": 0, "slot_id": 9})
	show("move slot 9 back to inventory", st, 200, body)

	st, body = req("POST", "/api/item/inv", access, map[string]any{"group_id": 0})
	show("inventory after slot2inv (item 1 restored)", st, 200, body)

	st, body = req("POST", "/api/item/inv2slot", access, map[string]any{"group_id": 0})
	show("inv2slot missing item_id/slot_id", st, 400, body)

	section("STATE + QUESTIONS")

	st, body = req("GET", "/api/state", access, nil)
	show("get state (default)", st, 200, body)

	st, body = req("POST", "/api/state", access, map[string]any{"state": "QUIZ"})
	show("teacher sets state QUIZ", st, 200, body)

	st, body = req("POST", "/api/state", sAccess, map[string]any{"state": "NORMAL"})
	show("student tries to set state (forbidden)", st, 403, body)

	st, body = req("POST", "/api/state", access, map[string]any{"state": "BOGUS"})
	show("set invalid state value", st, 400, body)

	st, body = req("POST", "/api/question/generate", access, map[string]any{"group_id": 0})
	show("teacher generates a question", st, 200, body)
	var q struct {
		Session string `json:"session"`
	}
	json.Unmarshal([]byte(body), &q)

	st, body = req("POST", "/api/question/answer", access, map[string]any{"session": q.Session, "answer": 1})
	show("answer generated question (answer=1)", st, 200, body)

	st, body = req("POST", "/api/question/answer", access, map[string]any{"session": q.Session, "answer": 1})
	show("answer same session again (consumed)", st, 400, body)

	st, body = req("POST", "/api/question/answer", access, map[string]any{"answer": 0})
	show("answer missing session", st, 400, body)

	st, _ = req("POST", "/api/state", access, map[string]any{"state": "NORMAL"})
	show("teacher sets state NORMAL", st, 200, "")

	st, body = req("POST", "/api/question/generate", sAccess, map[string]any{"group_id": 0})
	show("student generates in NORMAL (blocked)", st, 403, body)

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
