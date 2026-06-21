// Start the server (go run ./cmd/server) and then run `go run ./cmd/smoke` to
// fire real HTTP requests at every route described in README.md and print the
// status code + response body so the behavior can be eyeballed.
//
// The script only assumes the seeded admin account (ADMIN_USERNAME /
// ADMIN_PASSWORD, default admin/admin123) exists; every other fixture it needs
// (a teacher, a student, a building, a question pool, ...) is created through
// the API itself. Disposable usernames and ids are suffixed with a per-run
// timestamp so the script can be re-run against the same (persistent) Postgres
// database without colliding with a previous run's leftovers.
package main

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
)

// localhost:80 is just an nginx redirect stub to https in this deployment;
// Go's client demotes POST to GET on 301/302, which breaks every POST route,
// so default straight to the TLS listener.
var base = getenv("SMOKE_BASE_URL", "https://localhost")
var wsBase = getenv("SMOKE_WS_BASE_URL", toWsURL(base))

// client skips TLS certificate verification so the smoke script can run
// against a server using a self-signed certificate (e.g. local HTTPS dev).
var client = &http.Client{
	Timeout: 5 * time.Second,
	Transport: &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	},
}

var checks, fails int

// Item-generation constants tie the smoke building's difficulty_type map to
// the question pool's area-1 questions so generate's random picks (single
// candidate per difficulty) stay deterministic.
const (
	itemDifficulty1  = 1 // building difficulty_type "1" -> item type 10
	itemDifficulty2  = 2 // building difficulty_type "2" -> item type 20
	itemDiff1Answer  = 1 // correct choice index for the area-1/difficulty-1 question
	itemDiff2Answer  = 0 // correct choice index for the area-1/difficulty-2 question
	repairAreaAnswer = 0 // correct choice index for the area-2 (repair) question
)

func getenv(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}

// toWsURL derives the websocket base URL from the HTTP base URL by swapping
// the scheme (http -> ws, https -> wss), so SMOKE_BASE_URL alone is enough to
// point the whole script at an HTTPS server.
func toWsURL(httpBase string) string {
	switch {
	case strings.HasPrefix(httpBase, "https://"):
		return "wss://" + strings.TrimPrefix(httpBase, "https://")
	case strings.HasPrefix(httpBase, "http://"):
		return "ws://" + strings.TrimPrefix(httpBase, "http://")
	default:
		return httpBase
	}
}

// req sends method+path with an optional bearer token and JSON body, returning
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

// reqMultipart sends a multipart/form-data POST. When includeFile is true the
// payload is carried under the "file" field; otherwise an unrelated field is
// sent instead, to exercise the missing-file error path.
func reqMultipart(path, token, filename string, data []byte, includeFile bool) (int, string) {
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	if includeFile {
		fw, err := mw.CreateFormFile("file", filename)
		if err != nil {
			return -1, err.Error()
		}
		if _, err := fw.Write(data); err != nil {
			return -1, err.Error()
		}
	} else {
		_ = mw.WriteField("note", "no file field")
	}
	_ = mw.Close()

	r, err := http.NewRequest("POST", base+path, &buf)
	if err != nil {
		return -1, err.Error()
	}
	r.Header.Set("Content-Type", mw.FormDataContentType())
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

// pngBytes is just the 8-byte PNG signature http.DetectContentType keys off
// of; the upload path never decodes the image, so nothing past the header
// matters.
var pngBytes = []byte("\x89PNG\r\n\x1a\n")

// wavBytes is the minimal RIFF/WAVE header http.DetectContentType recognizes
// ("RIFF" + 4 masked size bytes + "WAVE"); the rest of a real WAV file is
// never read by the upload path.
var wavBytes = []byte("RIFF\x00\x00\x00\x00WAVE")

// show prints one check, comparing the actual status against what we expect.
func show(title string, status int, want int, body string) {
	checks++
	mark := "OK"
	if status != want {
		mark = "XX"
		fails++
	}
	fmt.Printf("[%s] %-58s -> %d (want %d)\n", mark, title, status, want)
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

// idOf resolves a username to its numeric id via GET /api/users/{username}.
// Returns 0 if not found.
func idOf(access, username string) uint {
	_, body := req("GET", "/api/users/"+username, access, nil)
	var u struct {
		ID uint `json:"id"`
	}
	json.Unmarshal([]byte(body), &u)
	return u.ID
}

// userAccountChecks exercises profile-picture, username-rename, password-change,
// and account-deletion against disposable accounts, so the teacher/student
// tokens the later sections share are never invalidated along the way.
func userAccountChecks(adminAccess, adminUsername, teacherAccess, runID string) {
	pfpUser := "pfptarget-" + runID
	renameUser := "renamer-" + runID
	pwUser := "pwchanger-" + runID
	gone1 := "throwaway1-" + runID
	gone2 := "throwaway2-" + runID

	req("POST", "/api/register", teacherAccess, map[string]any{"username": pfpUser, "password": "pw", "role": 0})
	_, body := req("POST", "/api/login", "", map[string]any{"username": pfpUser, "password": "pw"})
	pfpAccess, _ := tokens(body)

	st, _ := req("POST", "/api/users/pfp", pfpAccess, map[string]any{"profile_pic_url": "/images/self.jpg"})
	show("user sets own profile picture", st, 200, "")

	pfpID := idOf(adminAccess, pfpUser)

	st, body = req("POST", "/api/users/pfp", pfpAccess, map[string]any{"user_id": 999999999, "profile_pic_url": "/images/x.jpg"})
	show("user sets another user's picture (forbidden)", st, 403, body)

	st, _ = req("POST", "/api/users/pfp", teacherAccess, map[string]any{"user_id": pfpID, "profile_pic_url": "/images/teacher-set.jpg"})
	show("teacher sets another user's picture", st, 200, "")

	st, body = req("POST", "/api/users/pfp", teacherAccess, map[string]any{"user_id": 999999999, "profile_pic_url": "/images/x.jpg"})
	show("set picture for unknown user (404)", st, 404, body)

	// --- rename ---
	req("POST", "/api/register", teacherAccess, map[string]any{"username": renameUser, "password": "pw", "role": 0})
	_, body = req("POST", "/api/login", "", map[string]any{"username": renameUser, "password": "pw"})
	rAccess, _ := tokens(body)

	st, body = req("POST", "/api/users/username", rAccess, map[string]any{})
	show("rename missing username (rejected)", st, 400, body)

	st, body = req("POST", "/api/users/username", rAccess, map[string]any{"username": adminUsername})
	show("rename to a taken username (conflict)", st, 409, body)

	renamedUser := renameUser + "-renamed"
	st, _ = req("POST", "/api/users/username", rAccess, map[string]any{"username": renamedUser})
	show("user renames self", st, 200, "")

	// The access token minted before the rename carries the user's immutable id,
	// so it must keep working afterward (no forced re-login).
	st, body = req("GET", "/api/users", rAccess, nil)
	show("old access token still valid after rename", st, 200, body)

	st, body = req("POST", "/api/login", "", map[string]any{"username": renameUser, "password": "pw"})
	show("login with old username after rename (rejected)", st, 401, body)

	st, body = req("POST", "/api/login", "", map[string]any{"username": renamedUser, "password": "pw"})
	show("login with new username after rename", st, 200, body)

	// --- password change ---
	req("POST", "/api/register", teacherAccess, map[string]any{"username": pwUser, "password": "oldpw", "role": 0})
	_, body = req("POST", "/api/login", "", map[string]any{"username": pwUser, "password": "oldpw"})
	pAccess, _ := tokens(body)

	st, body = req("POST", "/api/users/password", pAccess, map[string]any{"old_password": "wrong", "new_password": "newpw"})
	show("change password with wrong current password (rejected)", st, 401, body)

	st, _ = req("POST", "/api/users/password", pAccess, map[string]any{"old_password": "oldpw", "new_password": "newpw"})
	show("change own password", st, 200, "")

	st, body = req("POST", "/api/login", "", map[string]any{"username": pwUser, "password": "oldpw"})
	show("login with old password after change (rejected)", st, 401, body)

	st, body = req("POST", "/api/login", "", map[string]any{"username": pwUser, "password": "newpw"})
	show("login with new password after change", st, 200, body)

	// --- delete ---
	req("POST", "/api/register", teacherAccess, map[string]any{"username": gone1, "password": "pw", "role": 0})
	gone1ID := idOf(adminAccess, gone1)

	st, body = req("DELETE", fmt.Sprintf("/api/users/%d", gone1ID), pAccess, nil)
	show("student deletes a user (forbidden)", st, 403, body)

	st, body = req("DELETE", fmt.Sprintf("/api/users/%d", gone1ID), adminAccess, nil)
	show("admin deletes a user", st, 200, body)

	st, body = req("DELETE", fmt.Sprintf("/api/users/%d", gone1ID), adminAccess, nil)
	show("delete already-deleted user (404)", st, 404, body)

	st, body = req("DELETE", fmt.Sprintf("/api/users/%d", idOf(adminAccess, adminUsername)), adminAccess, nil)
	show("admin tries to delete self (forbidden)", st, 403, body)

	req("POST", "/api/register", teacherAccess, map[string]any{"username": gone2, "password": "pw", "role": 0})
	st, body = req("DELETE", fmt.Sprintf("/api/users/%d", idOf(adminAccess, gone2)), teacherAccess, nil)
	show("teacher deletes a user", st, 200, body)
}

// buildingChecks exercises the building CRUD endpoints and returns the id of
// the building created, for later sections to assign/use.
func buildingChecks(adminAccess, studentAccess string) uint {
	itemAllowedSlot := map[string]any{"10": []int{0, 1}, "20": []int{2}}
	difficultyType := map[string]any{"1": []int{10}, "2": []int{20}}

	st, body := req("POST", "/api/building", adminAccess, map[string]any{
		"name":              "Smoke Library",
		"layout":            `{"w":3,"h":2}`,
		"item_allowed_slot": itemAllowedSlot,
		"difficulty_type":   difficultyType,
	})
	show("admin creates a building", st, 200, body)
	var b struct {
		BuildingID uint `json:"building_id"`
	}
	json.Unmarshal([]byte(body), &b)

	st, body = req("POST", "/api/building", adminAccess, map[string]any{})
	show("create building missing name (rejected)", st, 400, body)

	st, body = req("POST", "/api/building", studentAccess, map[string]any{"name": "Nope"})
	show("student creates a building (forbidden)", st, 403, body)

	st, body = req("GET", "/api/building", adminAccess, nil)
	show("list buildings", st, 200, body)

	idPath := fmt.Sprintf("/api/building/%d", b.BuildingID)
	st, body = req("GET", idPath, studentAccess, nil)
	show("get building by id", st, 200, body)

	st, body = req("GET", "/api/building/not-a-number", adminAccess, nil)
	show("get building with non-numeric id (rejected)", st, 400, body)

	st, body = req("GET", "/api/building/999999999", adminAccess, nil)
	show("get unknown building id (404)", st, 404, body)

	st, body = req("PUT", idPath, adminAccess, map[string]any{
		"name":              "Smoke Library",
		"layout":            `{"w":4,"h":2}`,
		"item_allowed_slot": itemAllowedSlot,
		"difficulty_type":   difficultyType,
	})
	show("admin updates building", st, 200, body)

	st, body = req("PUT", idPath, studentAccess, map[string]any{"name": "Nope"})
	show("student updates building (forbidden)", st, 403, body)

	st, body = req("PUT", "/api/building/999999999", adminAccess, map[string]any{"name": "Ghost"})
	show("update unknown building (404)", st, 404, body)

	return b.BuildingID
}

// studentChecks exercises the student CRUD endpoints and the roster-assignment
// endpoint, using a freshly minted student id so reruns never collide.
func studentChecks(adminAccess, studentAccess, rosterTarget string) {
	st, body := req("POST", "/api/student", adminAccess, map[string]any{"name": "Alice"})
	show("admin creates a student", st, 200, body)
	var created struct {
		StudentID uint `json:"student_id"`
	}
	json.Unmarshal([]byte(body), &created)
	sid := created.StudentID

	st, body = req("POST", "/api/student", adminAccess, map[string]any{})
	show("create student missing name (rejected)", st, 400, body)

	st, body = req("POST", "/api/student", studentAccess, map[string]any{"name": "Nope"})
	show("student creates a student (forbidden)", st, 403, body)

	st, body = req("GET", "/api/student", adminAccess, nil)
	show("list students", st, 200, body)

	sidPath := fmt.Sprintf("/api/student/%d", sid)
	st, body = req("GET", sidPath, studentAccess, nil)
	show("get student by id", st, 200, body)

	st, body = req("GET", "/api/student/999999999", adminAccess, nil)
	show("get unknown student id (404)", st, 404, body)

	st, body = req("PUT", sidPath, adminAccess, map[string]any{"name": "Alice Updated"})
	show("admin updates student", st, 200, body)

	st, body = req("PUT", "/api/student/999999999", adminAccess, map[string]any{"name": "Ghost"})
	show("update unknown student (404)", st, 404, body)

	st, body = req("POST", "/api/users/students", adminAccess, map[string]any{
		"user_id": idOf(adminAccess, rosterTarget), "student_ids": []uint{sid, 999999999},
	})
	show("assign roster (207 multi-status)", st, 207, body)

	st, body = req("POST", "/api/users/students", adminAccess, map[string]any{"student_ids": []uint{sid}})
	show("assign roster missing user_id (rejected)", st, 400, body)

	st, body = req("DELETE", sidPath, adminAccess, nil)
	show("admin deletes student", st, 200, body)

	st, body = req("DELETE", sidPath, adminAccess, nil)
	show("delete already-deleted student (404)", st, 404, body)

	st, body = req("DELETE", "/api/student/999999999", studentAccess, nil)
	show("student deletes a student (forbidden)", st, 403, body)
}

// questionPoolChecks exercises question pool management (upload/search/get/
// update/delete) and seeds the two area-1 questions (difficulty 1 and 2) plus
// the area-2 question that stateItemsQuestions relies on for item generation
// and slot repair.
func questionPoolChecks(adminAccess, studentAccess string) {
	st, body := req("POST", "/api/question/upload", adminAccess, map[string]any{
		"questions": []map[string]any{
			{ // area 1 / difficulty 1 -> drives item generation for type 10
				"content": map[string]any{
					"description": map[string]any{"type": "text", "data": "Smoke Q1: pick B"},
					"choices":     map[string]any{"type": "text", "data": []string{"A", "B", "C", "D"}},
				},
				"answer":     map[string]any{"type": "index", "data": []int{itemDiff1Answer}},
				"difficulty": itemDifficulty1,
				"area":       1,
			},
			{ // area 1 / difficulty 2 -> drives item generation for type 20
				"content": map[string]any{
					"description": map[string]any{"type": "text", "data": "Smoke Q2: pick A"},
					"choices":     map[string]any{"type": "text", "data": []string{"A", "B"}},
				},
				"answer":     map[string]any{"type": "index", "data": []int{itemDiff2Answer}},
				"difficulty": itemDifficulty2,
				"area":       1,
			},
			{ // area 2 -> drives the repair flow
				"content": map[string]any{
					"description": map[string]any{"type": "text", "data": "Smoke Q3 repair: pick A"},
					"choices":     map[string]any{"type": "text", "data": []string{"A", "B"}},
				},
				"answer": map[string]any{"type": "index", "data": []int{repairAreaAnswer}},
				"area":   2,
			},
			{ // invalid: empty description, should be rejected rather than fail the batch
				"content": map[string]any{"description": map[string]any{"type": "text", "data": ""}},
				"answer":  map[string]any{"type": "index", "data": []int{0}},
			},
			{ // disposable, only used to exercise get/search/update/delete below
				"content": map[string]any{
					"description": map[string]any{"type": "text", "data": "Smoke Q5 disposable"},
					"choices":     map[string]any{"type": "text", "data": []string{"A", "B"}},
				},
				"answer":     map[string]any{"type": "index", "data": []int{0}},
				"difficulty": 77,
				"area":       77,
			},
		},
	})
	show("teacher uploads a question batch (207 multi-status)", st, 207, body)

	var up struct {
		Results []struct {
			ID uint `json:"id"`
		} `json:"results"`
	}
	json.Unmarshal([]byte(body), &up)
	var disposableID uint
	if len(up.Results) == 5 {
		disposableID = up.Results[4].ID
	}

	st, body = req("POST", "/api/question/upload", studentAccess, map[string]any{"questions": []map[string]any{{}}})
	show("student uploads questions (forbidden)", st, 403, body)

	st, body = req("POST", "/api/question/upload", adminAccess, map[string]any{"questions": []map[string]any{}})
	show("upload empty question list (rejected)", st, 400, body)

	st, body = req("GET", "/api/question/search?difficulty=77&area=77", adminAccess, nil)
	show("search questions by difficulty+area", st, 200, body)

	st, body = req("GET", "/api/question/search?difficulty=not-a-number", adminAccess, nil)
	show("search with invalid difficulty (rejected)", st, 400, body)

	st, body = req("GET", "/api/question/search", studentAccess, nil)
	show("student searches questions (forbidden)", st, 403, body)

	disposablePath := fmt.Sprintf("/api/question/%d", disposableID)
	st, body = req("GET", disposablePath, studentAccess, nil)
	show("get question by id (any user)", st, 200, body)

	st, body = req("GET", "/api/question/999999999", adminAccess, nil)
	show("get unknown question id (404)", st, 404, body)

	st, body = req("PUT", disposablePath, adminAccess, map[string]any{
		"content": map[string]any{
			"description": map[string]any{"type": "text", "data": "Smoke Q5 updated"},
			"choices":     map[string]any{"type": "text", "data": []string{"A", "B"}},
		},
		"answer":     map[string]any{"type": "index", "data": []int{0}},
		"difficulty": 77,
		"area":       77,
	})
	show("admin updates question", st, 200, "")

	st, body = req("PUT", disposablePath, studentAccess, map[string]any{})
	show("student updates question (forbidden)", st, 403, body)

	st, body = req("PUT", "/api/question/999999999", adminAccess, map[string]any{
		"content": map[string]any{"description": map[string]any{"type": "text", "data": "x"}},
		"answer":  map[string]any{"type": "index", "data": []int{0}},
	})
	show("update unknown question (404)", st, 404, body)

	st, body = req("DELETE", disposablePath, adminAccess, nil)
	show("admin deletes question", st, 200, body)

	st, body = req("DELETE", disposablePath, adminAccess, nil)
	show("delete already-deleted question (404)", st, 404, body)
}

// stateItemsQuestions exercises the server state machine together with the
// item-generation, inventory-movement, and attack/repair question flows. The
// teacher token bypasses every state gate; the student token is used to prove
// the gates themselves (QUIZ1 for generate, QUIZ2 for target).
func stateItemsQuestions(adminAccess, teacherAccess, teacherUsername, studentAccess, studentUsername string) {
	teacherID := idOf(adminAccess, teacherUsername)
	studentID := idOf(adminAccess, studentUsername)

	st, body := req("GET", "/api/state", adminAccess, nil)
	show("get state (default)", st, 200, body)

	st, _ = req("POST", "/api/state", adminAccess, map[string]any{"state": "QUIZ1"})
	show("admin sets state QUIZ1", st, 200, "")

	st, body = req("POST", "/api/state", studentAccess, map[string]any{"state": "NORMAL"})
	show("student tries to set state (forbidden)", st, 403, body)

	st, body = req("POST", "/api/state", adminAccess, map[string]any{"state": "BOGUS"})
	show("set invalid state value", st, 400, body)

	var q struct {
		Session string `json:"session"`
	}
	var ans struct {
		ItemID uint `json:"item_id"`
	}

	// --- teacher earns a type-10 item (bypasses the QUIZ1 gate) ---
	st, body = req("POST", "/api/question/generate", teacherAccess, map[string]any{"difficulty": itemDifficulty1})
	show("teacher generates a type-10 item (difficulty 1)", st, 200, body)
	json.Unmarshal([]byte(body), &q)

	st, body = req("POST", "/api/question/answer", teacherAccess, map[string]any{"session": q.Session, "answer": itemDiff1Answer})
	show("answer correctly -> item granted (item_id)", st, 200, body)
	json.Unmarshal([]byte(body), &ans)
	item10 := ans.ItemID

	st, body = req("POST", "/api/question/answer", teacherAccess, map[string]any{"session": q.Session, "answer": itemDiff1Answer})
	show("answer same session again (consumed)", st, 400, body)

	st, body = req("POST", "/api/question/answer", teacherAccess, map[string]any{"answer": 0})
	show("answer missing session", st, 400, body)

	st, body = req("POST", "/api/question/generate", teacherAccess, map[string]any{"difficulty": 9})
	show("generate item for a difficulty with no type (rejected)", st, 400, body)

	// --- teacher earns a type-20 item too, for the "type not allowed" check below ---
	st, body = req("POST", "/api/question/generate", teacherAccess, map[string]any{"difficulty": itemDifficulty2})
	show("teacher generates a type-20 item (difficulty 2)", st, 200, body)
	json.Unmarshal([]byte(body), &q)

	st, body = req("POST", "/api/question/answer", teacherAccess, map[string]any{"session": q.Session, "answer": itemDiff2Answer})
	show("answer correctly -> item granted (item_id)", st, 200, body)
	json.Unmarshal([]byte(body), &ans)
	item20 := ans.ItemID

	// --- items ---
	st, body = req("POST", "/api/item", teacherAccess, map[string]any{})
	show("query items with missing user_id (rejected)", st, 400, body)

	st, body = req("POST", "/api/item", teacherAccess, map[string]any{"user_id": teacherID})
	show("query own items (inventory + slots)", st, 200, body)

	st, body = req("POST", "/api/item/inv2slot", teacherAccess, map[string]any{"user_id": teacherID, "item_id": 0, "slot_id": 1})
	show("inv2slot with item_id 0 (rejected)", st, 400, body)

	st, _ = req("POST", "/api/item/inv2slot", teacherAccess, map[string]any{"user_id": teacherID, "item_id": item10, "slot_id": 1})
	show("move type-10 item into allowed slot 1", st, 200, "")

	st, body = req("POST", "/api/item", teacherAccess, map[string]any{"user_id": teacherID})
	show("items after inv2slot", st, 200, body)

	st, body = req("POST", "/api/item/inv2slot", teacherAccess, map[string]any{"user_id": teacherID, "item_id": item20, "slot_id": 1})
	show("move type-20 item into slot 1 (type not allowed)", st, 400, body)

	st, body = req("POST", "/api/item/inv2slot", teacherAccess, map[string]any{"user_id": teacherID, "item_id": 999999999, "slot_id": 1})
	show("move item not in inventory (rejected)", st, 400, body)

	st, body = req("POST", "/api/item/slot2inv", teacherAccess, map[string]any{"user_id": teacherID, "slot_id": 1})
	show("move slot 1 back to inventory", st, 200, body)

	st, body = req("POST", "/api/item", teacherAccess, map[string]any{"user_id": teacherID})
	show("items after slot2inv (item restored)", st, 200, body)

	st, body = req("POST", "/api/item/inv2slot", teacherAccess, map[string]any{"user_id": teacherID})
	show("inv2slot missing item_id/slot_id", st, 400, body)

	// --- student generate, gated by QUIZ1 ---
	st, _ = req("POST", "/api/state", adminAccess, map[string]any{"state": "NORMAL"})
	show("admin sets state NORMAL", st, 200, "")

	st, body = req("POST", "/api/question/generate", studentAccess, map[string]any{"difficulty": itemDifficulty1})
	show("student generates item outside QUIZ1 (blocked)", st, 403, body)

	st, _ = req("POST", "/api/state", adminAccess, map[string]any{"state": "QUIZ1"})
	show("admin sets state QUIZ1", st, 200, "")

	st, body = req("POST", "/api/question/generate", studentAccess, map[string]any{"difficulty": itemDifficulty1})
	show("student generates item during QUIZ1", st, 200, body)
	json.Unmarshal([]byte(body), &q)

	st, body = req("POST", "/api/question/answer", studentAccess, map[string]any{"session": q.Session, "answer": itemDiff1Answer})
	show("student answers correctly -> item granted", st, 200, body)

	st, body = req("POST", "/api/item", studentAccess, map[string]any{"user_id": studentID})
	show("student queries own items", st, 200, body)

	// --- attack/repair flow (QUIZ2) ---
	st, _ = req("POST", "/api/item/inv2slot", teacherAccess, map[string]any{"user_id": teacherID, "item_id": item10, "slot_id": 1})
	show("re-slot the type-10 item for the attack/repair flow", st, 200, "")

	st, _ = req("POST", "/api/state", adminAccess, map[string]any{"state": "QUIZ2"})
	show("admin sets state QUIZ2", st, 200, "")

	st, body = req("POST", "/api/question/target", studentAccess, map[string]any{"target_user_id": teacherID, "target_slot_id": 1})
	show("student targets teacher's slot 1 (attack)", st, 200, body)
	json.Unmarshal([]byte(body), &q)

	st, body = req("POST", "/api/question/answer", studentAccess, map[string]any{"session": q.Session, "answer": itemDiff1Answer})
	show("answer correctly -> break the item (success)", st, 200, body)

	st, body = req("POST", "/api/item", teacherAccess, map[string]any{"user_id": teacherID})
	show("teacher items (slot 1 now broken)", st, 200, body)

	st, body = req("POST", "/api/question/target", teacherAccess, map[string]any{"target_user_id": teacherID, "target_slot_id": 1})
	show("teacher targets own broken slot (repair)", st, 200, body)
	json.Unmarshal([]byte(body), &q)

	st, body = req("POST", "/api/question/answer", teacherAccess, map[string]any{"session": q.Session, "answer": repairAreaAnswer})
	show("answer correctly -> repair the item (success)", st, 200, body)

	st, body = req("POST", "/api/question/target", teacherAccess, map[string]any{"target_user_id": teacherID, "target_slot_id": 1})
	show("target own non-broken slot (invalid)", st, 400, body)

	st, body = req("POST", "/api/question/generate", studentAccess, map[string]any{"difficulty": itemDifficulty1})
	show("student generates item in QUIZ2 (blocked)", st, 403, body)

	st, _ = req("POST", "/api/state", adminAccess, map[string]any{"state": "NORMAL"})
	show("admin sets state NORMAL", st, 200, "")
}

// mediaChecks exercises image/audio upload, relying only on the magic-byte
// signatures http.DetectContentType keys off of.
func mediaChecks(token string) {
	st, body := reqMultipart("/api/image", token, "smoke.png", pngBytes, true)
	show("upload a PNG image", st, 201, body)

	st, body = reqMultipart("/api/image", token, "smoke.txt", []byte("not an image"), true)
	show("upload an unsupported image format (rejected)", st, 415, body)

	st, body = reqMultipart("/api/image", token, "smoke.png", pngBytes, false)
	show("upload image with no file field (rejected)", st, 400, body)

	st, body = reqMultipart("/api/image", "", "smoke.png", pngBytes, true)
	show("upload image without token", st, 401, body)

	st, body = reqMultipart("/api/audio", token, "smoke.wav", wavBytes, true)
	show("upload a WAV audio file", st, 201, body)

	st, body = reqMultipart("/api/audio", token, "smoke.txt", []byte("not audio"), true)
	show("upload an unsupported audio format (rejected)", st, 415, body)
}

// --- state websocket ---

type stateEvent struct {
	State     string     `json:"state"`
	UpdatedAt time.Time  `json:"updated_at"`
	EndTime   *time.Time `json:"end_time,omitempty"`
}

func readEvent(ctx context.Context, c *websocket.Conn) (stateEvent, error) {
	var ev stateEvent
	err := wsjson.Read(ctx, c, &ev)
	return ev, err
}

func showWS(title string, ev stateEvent, err error, wantState string) {
	checks++
	if err != nil {
		fails++
		fmt.Printf("[XX] %-58s -> error: %v\n", title, err)
		return
	}
	mark := "OK"
	if wantState != "" && ev.State != wantState {
		mark = "XX"
		fails++
	}
	fmt.Printf("[%s] %-58s -> state=%s updated_at=%s\n", mark, title, ev.State, ev.UpdatedAt.Format(time.RFC3339))
}

// wsChecks connects to the state websocket, checks the initial snapshot, then
// drives a couple of state transitions through the REST API and confirms they
// are pushed to the socket. Assumes the state is NORMAL on entry and leaves it
// NORMAL on exit.
func wsChecks(access, sAccess string) {
	st, body := req("GET", "/api/state/ws", "", nil)
	show("connect to state ws without token (rejected)", st, 401, body)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	c, _, err := websocket.Dial(ctx, wsBase+"/api/state/ws?access_token="+sAccess, &websocket.DialOptions{HTTPClient: client})
	if err != nil {
		fmt.Printf("[XX] connect to state ws via query param -> error: %v\n", err)
		fails++
		checks++
		return
	}
	defer c.CloseNow()

	ev, err := readEvent(ctx, c)
	showWS("initial snapshot over ws", ev, err, "NORMAL")

	st, _ = req("POST", "/api/state", access, map[string]any{"state": "QUIZ1"})
	show("admin sets state QUIZ1", st, 200, "")

	ev, err = readEvent(ctx, c)
	showWS("ws push on transition to QUIZ1", ev, err, "QUIZ1")

	st, _ = req("POST", "/api/state", access, map[string]any{"state": "NORMAL"})
	show("admin sets state NORMAL", st, 200, "")

	ev, err = readEvent(ctx, c)
	showWS("ws push on transition to NORMAL", ev, err, "NORMAL")

	c.Close(websocket.StatusNormalClosure, "")
}

// allReceived blocks until every subscriber channel has produced at least one
// event matching wantState, or the context expires.
func allReceived(ctx context.Context, conns []*websocket.Conn, wantState string) bool {
	for _, c := range conns {
		ev, err := readEvent(ctx, c)
		if err != nil || ev.State != wantState {
			return false
		}
	}
	return true
}

// wsFanout opens several state-websocket subscribers at once and checks that a
// single state transition is broadcast to all of them.
func wsFanout(access, sAccess string) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	var conns []*websocket.Conn
	for i := range 3 {
		c, _, err := websocket.Dial(ctx, wsBase+"/api/state/ws?access_token="+sAccess, &websocket.DialOptions{HTTPClient: client})
		if err != nil {
			fmt.Printf("[XX] open fanout subscriber %d -> error: %v\n", i, err)
			fails++
			checks++
			return
		}
		defer c.CloseNow()
		conns = append(conns, c)
	}

	// Drain each subscriber's initial snapshot before triggering the transition.
	for _, c := range conns {
		readEvent(ctx, c)
	}

	st, _ := req("POST", "/api/state", access, map[string]any{"state": "QUIZ2"})
	show("admin sets state QUIZ2", st, 200, "")

	checks++
	if allReceived(ctx, conns, "QUIZ2") {
		fmt.Printf("[OK] %-58s -> all %d subscribers received QUIZ2\n", "fanout to multiple ws subscribers", len(conns))
	} else {
		fails++
		fmt.Printf("[XX] %-58s -> not all subscribers received QUIZ2\n", "fanout to multiple ws subscribers")
	}

	st, _ = req("POST", "/api/state", access, map[string]any{"state": "NORMAL"})
	show("admin sets state NORMAL", st, 200, "")

	for _, c := range conns {
		c.Close(websocket.StatusNormalClosure, "")
	}
}

func main() {
	runID := fmt.Sprintf("%d", time.Now().UnixNano()%1_000_000)

	section("AUTH")

	adminUsername := getenv("ADMIN_USERNAME", "admin")
	adminPassword := getenv("ADMIN_PASSWORD", "admin123")

	st, _ := req("POST", "/api/login", "", map[string]any{"username": adminUsername, "password": "wrong-" + adminPassword})
	show("login with wrong password", st, 401, "")

	st, body := req("POST", "/api/login", "", map[string]any{"username": adminUsername, "password": adminPassword})
	show("login as seeded admin", st, 200, body)
	access, refresh := tokens(body)
	if access == "" {
		fmt.Printf("\nFATAL: could not obtain an access token for %q; is the server running at %s with that admin account?\n", adminUsername, base)
		os.Exit(1)
	}

	st, _ = req("GET", "/api/users", "", nil)
	show("GET /api/users without token", st, 401, "")

	st, body = req("GET", "/api/users", access, nil)
	show("GET /api/users with token", st, 200, body)

	st, body = req("GET", "/api/users/"+adminUsername, access, nil)
	show("GET /api/users/{username} (lookup)", st, 200, body)

	st, body = req("GET", "/api/users/no-such-user", access, nil)
	show("GET /api/users/{username} unknown (404)", st, 404, body)

	section("REGISTER (teacher-only)")

	teacherUsername := "teacher1-" + runID
	studentUsername := "stud1-" + runID

	st, _ = req("POST", "/api/register", access, map[string]any{"username": teacherUsername, "password": "pw", "role": 1})
	show("admin registers a teacher", st, 201, "")

	st, body = req("POST", "/api/register", access, map[string]any{"username": teacherUsername, "password": "pw", "role": 1})
	show("register duplicate username", st, 409, body)

	st, body = req("POST", "/api/register", access, map[string]any{"username": "admin1-" + runID, "password": "pw", "role": 2})
	show("admin tries to create an admin (role 2, forbidden)", st, 403, body)

	st, body = req("POST", "/api/register", access, map[string]any{"username": "norole-" + runID, "password": "pw"})
	show("register missing role", st, 400, body)

	st, body = req("POST", "/api/login", "", map[string]any{"username": teacherUsername, "password": "pw"})
	show("login as new teacher", st, 200, body)
	tAccess, _ := tokens(body)

	st, _ = req("POST", "/api/register", tAccess, map[string]any{"username": studentUsername, "password": "pw", "role": 0})
	show("teacher registers a student", st, 201, "")

	st, body = req("POST", "/api/login", "", map[string]any{"username": studentUsername, "password": "pw"})
	show("login as new student", st, 200, body)
	sAccess, _ := tokens(body)

	st, body = req("POST", "/api/register", sAccess, map[string]any{"username": "x-" + runID, "password": "pw", "role": 0})
	show("student tries to register (forbidden)", st, 403, body)

	section("USER ACCOUNT MANAGEMENT")
	userAccountChecks(access, adminUsername, tAccess, runID)

	section("BUILDING CRUD")
	buildingID := buildingChecks(access, sAccess)

	section("STUDENT CRUD + ROSTER")
	studentChecks(access, sAccess, teacherUsername)

	section("QUESTION POOL MANAGEMENT")
	questionPoolChecks(access, sAccess)

	section("ASSIGN BUILDING")

	st, _ = req("POST", "/api/users/building", tAccess, map[string]any{"building_id": buildingID})
	show("teacher assigns building to self", st, 200, "")

	st, body = req("POST", "/api/users/building", tAccess, map[string]any{})
	show("assign building missing building_id (rejected)", st, 400, body)

	st, _ = req("POST", "/api/users/building", sAccess, map[string]any{"building_id": buildingID})
	show("student assigns building to self", st, 200, "")

	section("STATE + ITEMS + QUESTIONS")
	stateItemsQuestions(access, tAccess, teacherUsername, sAccess, studentUsername)

	section("MEDIA UPLOADS")
	mediaChecks(tAccess)

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
