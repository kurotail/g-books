// Package mock provides in-memory implementations of the repo interfaces for
// use in tests across the service and handler packages.
package mock

import (
	"fmt"
	"maps"
	"sort"
	"sync"
	"time"

	apperr "gb-api/internal/error"
	"gb-api/internal/model"
	"gb-api/internal/repo"
)

var (
	_ repo.UserRepo         = (*AuthRepo)(nil)
	_ repo.UserRepo         = (*RoleRepo)(nil)
	_ repo.RefreshTokenRepo = (*AuthRepo)(nil)
	_ repo.ItemRepo         = (*ItemRepo)(nil)
	_ repo.GroupRepo        = (*GroupRepo)(nil)
	_ repo.BuildingRepo     = (*BuildingRepo)(nil)
	_ repo.QuestionRepo     = (*QuestionRepo)(nil)
	_ repo.STTRepo          = (*STTRepo)(nil)
)

type AuthRepo struct {
	Users         map[string]string
	Roles         map[string]uint
	Groups        map[string]uint // username -> group; absent = no group
	Pics          map[string]string
	RefreshTokens sync.Map
}

func (m *AuthRepo) ValidateCredentials(username, password string) (bool, error) {
	stored, ok := m.Users[username]
	return ok && stored == password, nil
}

func (m *AuthRepo) StoreRefreshToken(jti string) error {
	m.RefreshTokens.Store(jti, struct{}{})
	return nil
}

func (m *AuthRepo) ConsumeRefreshToken(jti string) (bool, error) {
	_, ok := m.RefreshTokens.LoadAndDelete(jti)
	return ok, nil
}

func (m *AuthRepo) GetAllUsers() ([]model.User, error) {
	users := make([]model.User, 0, len(m.Users))
	for username := range m.Users {
		users = append(users, m.buildUser(username))
	}
	return users, nil
}

func (m *AuthRepo) GetUser(username string) (model.User, error) {
	if _, ok := m.Roles[username]; !ok {
		return model.User{}, apperr.ErrUserNotFound
	}
	return m.buildUser(username), nil
}

func (m *AuthRepo) buildUser(username string) model.User {
	return model.User{Username: username, Role: m.Roles[username], GroupID: m.Groups[username], ProfilePicURL: m.Pics[username]}
}

func (m *AuthRepo) SetUserProfilePic(username, url string) error {
	if _, ok := m.Roles[username]; !ok {
		return apperr.ErrUserNotFound
	}
	if m.Pics == nil {
		m.Pics = map[string]string{}
	}
	m.Pics[username] = url
	return nil
}

func (m *AuthRepo) CreateUser(username, password string, role, groupID uint) error {
	if _, ok := m.Users[username]; ok {
		return apperr.ErrUserExists
	}
	if m.Users == nil {
		m.Users = map[string]string{}
	}
	if m.Roles == nil {
		m.Roles = map[string]uint{}
	}
	if m.Groups == nil {
		m.Groups = map[string]uint{}
	}
	m.Users[username] = password
	m.Roles[username] = role
	m.Groups[username] = groupID
	return nil
}

func (m *AuthRepo) DeleteUser(username string) (bool, error) {
	if _, ok := m.Roles[username]; !ok {
		return false, nil
	}
	delete(m.Users, username)
	delete(m.Roles, username)
	delete(m.Groups, username)
	delete(m.Pics, username)
	return true, nil
}

type RoleRepo struct {
	Role uint
}

func (m *RoleRepo) ValidateCredentials(_, _ string) (bool, error) { return false, nil }
func (m *RoleRepo) GetAllUsers() ([]model.User, error)            { return nil, nil }
func (m *RoleRepo) GetUser(username string) (model.User, error) {
	return model.User{Username: username, Role: m.Role}, nil
}
func (m *RoleRepo) CreateUser(_, _ string, _, _ uint) error { return nil }
func (m *RoleRepo) SetUserProfilePic(_, _ string) error     { return nil }
func (m *RoleRepo) DeleteUser(_ string) (bool, error)       { return true, nil }

type ItemRepo struct {
	Inv        map[uint]struct{}   // owned (unslotted) item ids
	Slot       map[uint]int        // slot_id -> signed item_id
	Items      map[uint]model.Item // item table
	NextItemID uint                // next id assigned by CreateItem
}

func (m *ItemRepo) QueryInv(_ uint) ([]uint, error) {
	ids := make([]uint, 0, len(m.Inv))
	for id := range m.Inv {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	return ids, nil
}

func (m *ItemRepo) QuerySlot(_ uint) (map[uint]int, error) {
	result := make(map[uint]int, len(m.Slot))
	maps.Copy(result, m.Slot)
	return result, nil
}

func (m *ItemRepo) GetItem(itemID uint) (model.Item, bool, error) {
	it, ok := m.Items[itemID]
	return it, ok, nil
}

func (m *ItemRepo) CreateItem(itemType, questionID uint) (uint, error) {
	if m.Items == nil {
		m.Items = map[uint]model.Item{}
	}
	if m.NextItemID == 0 {
		m.NextItemID = 1000 // high base to avoid colliding with seeded item ids
	}
	id := m.NextItemID
	m.NextItemID++
	m.Items[id] = model.Item{ItemID: id, Type: itemType, QuestionID: questionID}
	return id, nil
}

func (m *ItemRepo) AddInvItem(_, itemID uint) error {
	if m.Inv == nil {
		m.Inv = map[uint]struct{}{}
	}
	m.Inv[itemID] = struct{}{}
	return nil
}

func (m *ItemRepo) RemoveInvItem(_, itemID uint) error {
	delete(m.Inv, itemID)
	return nil
}

func (m *ItemRepo) SetSlot(_, slotID uint, itemID int) error {
	if itemID == 0 {
		delete(m.Slot, slotID)
	} else {
		if m.Slot == nil {
			m.Slot = map[uint]int{}
		}
		m.Slot[slotID] = itemID
	}
	return nil
}

type GroupRepo struct {
	UserGroups  map[string]uint
	Names       map[uint]string
	BuildingIDs map[uint]uint
	Pics        map[uint]string
}

func (m *GroupRepo) SetUserGroup(username string, groupID uint) error {
	m.UserGroups[username] = groupID
	return nil
}

func (m *GroupRepo) GetGroup(groupID uint) (model.Group, error) {
	members := make([]string, 0)
	for username, gid := range m.UserGroups {
		if gid == groupID {
			members = append(members, username)
		}
	}
	_, hasName := m.Names[groupID]
	_, hasBuilding := m.BuildingIDs[groupID]
	_, hasPic := m.Pics[groupID]
	if !hasName && !hasBuilding && !hasPic && len(members) == 0 {
		return model.Group{}, apperr.ErrGroupNotFound
	}
	name := fmt.Sprintf("Group %d", groupID)
	if n, ok := m.Names[groupID]; ok && n != "" {
		name = n
	}
	return model.Group{ID: groupID, Name: name, BuildingID: m.BuildingIDs[groupID], Members: members, ProfilePicURL: m.Pics[groupID]}, nil
}

func (m *GroupRepo) SetGroupName(groupID uint, name string) error {
	if m.Names == nil {
		m.Names = map[uint]string{}
	}
	m.Names[groupID] = name
	return nil
}

func (m *GroupRepo) SetBuildingID(groupID uint, buildingID uint) error {
	if m.BuildingIDs == nil {
		m.BuildingIDs = map[uint]uint{}
	}
	m.BuildingIDs[groupID] = buildingID
	return nil
}

func (m *GroupRepo) SetGroupProfilePic(groupID uint, url string) error {
	if m.Pics == nil {
		m.Pics = map[uint]string{}
	}
	m.Pics[groupID] = url
	return nil
}

func (m *GroupRepo) DeleteGroup(groupID uint) (bool, error) {
	found := false
	if _, ok := m.Names[groupID]; ok {
		found = true
	}
	if _, ok := m.BuildingIDs[groupID]; ok {
		found = true
	}
	if _, ok := m.Pics[groupID]; ok {
		found = true
	}
	for username, gid := range m.UserGroups {
		if gid == groupID {
			m.UserGroups[username] = 0
			found = true
		}
	}
	if !found {
		return false, nil
	}
	delete(m.Names, groupID)
	delete(m.BuildingIDs, groupID)
	delete(m.Pics, groupID)
	return true, nil
}

type BuildingRepo struct {
	Buildings map[uint]model.Building
	NextID    uint
}

func (m *BuildingRepo) CreateBuilding(name, layout string, typeAllowedSlot map[uint][]uint, difficultyType map[uint][]uint) (uint, error) {
	if m.Buildings == nil {
		m.Buildings = map[uint]model.Building{}
	}
	if m.NextID == 0 {
		m.NextID = 1
	}
	id := m.NextID
	m.NextID++
	m.Buildings[id] = model.Building{ID: id, Name: name, Layout: layout, TypeAllowedSlot: typeAllowedSlot, DifficultyType: difficultyType}
	return id, nil
}

func (m *BuildingRepo) UpdateBuilding(id uint, name, layout string, typeAllowedSlot map[uint][]uint, difficultyType map[uint][]uint) error {
	if _, ok := m.Buildings[id]; !ok {
		return apperr.ErrBuildingNotFound
	}
	m.Buildings[id] = model.Building{ID: id, Name: name, Layout: layout, TypeAllowedSlot: typeAllowedSlot, DifficultyType: difficultyType}
	return nil
}

func (m *BuildingRepo) GetBuilding(id uint) (model.Building, error) {
	b, ok := m.Buildings[id]
	if !ok {
		return model.Building{}, apperr.ErrBuildingNotFound
	}
	return b, nil
}

func (m *BuildingRepo) GetAllBuildings() ([]model.Building, error) {
	out := make([]model.Building, 0, len(m.Buildings))
	for _, b := range m.Buildings {
		out = append(out, b)
	}
	return out, nil
}

type QuestionRepo struct {
	Sessions  map[string]model.QuestionSession
	Created   string
	Questions map[uint]model.Question
	NextID    uint
}

// StoreSession stores the session under a fixed id "session-id" (tests read it back
// via Created / Sessions).
func (m *QuestionRepo) StoreSession(sess model.QuestionSession) (string, error) {
	id := "session-id"
	if m.Sessions == nil {
		m.Sessions = map[string]model.QuestionSession{}
	}
	if sess.ExpiresAt.IsZero() {
		sess.ExpiresAt = time.Now().Add(15 * time.Minute)
	}
	m.Sessions[id] = sess
	m.Created = id
	return id, nil
}

// RandomQuestion returns the first question matching area (and difficulty when
// non-nil). Map iteration order is unspecified, which is fine for tests that seed a
// single matching question.
func (m *QuestionRepo) RandomQuestion(area uint, difficulty *uint) (uint, model.Question, bool, error) {
	for id, q := range m.Questions {
		if q.Area != area {
			continue
		}
		if difficulty != nil && q.Difficulty != *difficulty {
			continue
		}
		return id, q, true, nil
	}
	return 0, model.Question{}, false, nil
}

func (m *QuestionRepo) GetQuestion(id uint) (model.Question, bool, error) {
	q, ok := m.Questions[id]
	return q, ok, nil
}

func (m *QuestionRepo) ConsumeSession(session string) (model.QuestionSession, bool, error) {
	qs, ok := m.Sessions[session]
	if ok {
		delete(m.Sessions, session)
	}
	return qs, ok, nil
}

func (m *QuestionRepo) AddQuestions(qs []model.Question) ([]model.QuestionRecord, error) {
	if m.Questions == nil {
		m.Questions = map[uint]model.Question{}
	}
	if m.NextID == 0 {
		m.NextID = 1
	}
	records := make([]model.QuestionRecord, 0, len(qs))
	for _, q := range qs {
		id := m.NextID
		m.NextID++
		m.Questions[id] = q
		records = append(records, mockRecord(id, q))
	}
	return records, nil
}

func (m *QuestionRepo) SearchQuestions(difficulty, area *uint) ([]model.QuestionRecord, error) {
	records := make([]model.QuestionRecord, 0, len(m.Questions))
	for id, q := range m.Questions {
		if difficulty != nil && q.Difficulty != *difficulty {
			continue
		}
		if area != nil && q.Area != *area {
			continue
		}
		records = append(records, mockRecord(id, q))
	}
	sort.Slice(records, func(i, j int) bool { return records[i].ID < records[j].ID })
	return records, nil
}

func mockRecord(id uint, q model.Question) model.QuestionRecord {
	return model.QuestionRecord{
		ID:         id,
		Content:    q.Content,
		Answer:     q.Answer,
		Difficulty: q.Difficulty,
		Area:       q.Area,
	}
}

// STTRepo is a mock speech-to-text backend. Transcript is returned verbatim for any
// base64 WAV input, letting tests drive the voice_response grading outcome.
type STTRepo struct {
	Transcript string
}

func (m *STTRepo) Transcribe(wavB64 string) (string, error) {
	return m.Transcript, nil
}

func (m *QuestionRepo) UpdateQuestion(id uint, q model.Question) (bool, error) {
	if _, ok := m.Questions[id]; !ok {
		return false, nil
	}
	m.Questions[id] = q
	return true, nil
}

func (m *QuestionRepo) DeleteQuestion(id uint) (bool, error) {
	if _, ok := m.Questions[id]; !ok {
		return false, nil
	}
	delete(m.Questions, id)
	return true, nil
}
