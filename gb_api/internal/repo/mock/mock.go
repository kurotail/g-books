// Package mock provides in-memory implementations of the repo interfaces for
// use in tests across the service and handler packages.
package mock

import (
	"maps"
	"sort"
	"strings"
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
	_ repo.QuestionRepo     = (*QuestionRepo)(nil)
)

type AuthRepo struct {
	Users         map[string]string
	Roles         map[string]uint
	Groups        map[string]uint // username -> group; absent = no group
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
	u := model.User{Username: username, Role: m.Roles[username]}
	if gid, ok := m.Groups[username]; ok {
		u.GroupID = &gid
	}
	return u
}

func (m *AuthRepo) CreateUser(username, password string, role uint) error {
	if _, ok := m.Users[username]; ok {
		return apperr.ErrUserExists
	}
	if m.Users == nil {
		m.Users = map[string]string{}
	}
	if m.Roles == nil {
		m.Roles = map[string]uint{}
	}
	m.Users[username] = password
	m.Roles[username] = role
	return nil
}

type RoleRepo struct {
	Role uint
}

func (m *RoleRepo) ValidateCredentials(_, _ string) (bool, error) { return false, nil }
func (m *RoleRepo) GetAllUsers() ([]model.User, error)            { return nil, nil }
func (m *RoleRepo) GetUser(username string) (model.User, error) {
	return model.User{Username: username, Role: m.Role}, nil
}
func (m *RoleRepo) CreateUser(_, _ string, _ uint) error { return nil }

type ItemRepo struct {
	Inv  map[uint]uint
	Slot map[uint]uint
}

func (m *ItemRepo) QueryInv(_ uint) (map[uint]uint, error) {
	result := make(map[uint]uint, len(m.Inv))
	maps.Copy(result, m.Inv)
	return result, nil
}

func (m *ItemRepo) QuerySlot(_ uint) (map[uint]uint, error) {
	result := make(map[uint]uint, len(m.Slot))
	maps.Copy(result, m.Slot)
	return result, nil
}

func (m *ItemRepo) ChangeInv(_, itemID uint, delta int) error {
	next := int(m.Inv[itemID]) + delta
	if next < 0 {
		return apperr.ErrInsufficientStock
	}
	if next == 0 {
		delete(m.Inv, itemID)
	} else {
		m.Inv[itemID] = uint(next)
	}
	return nil
}

func (m *ItemRepo) SetSlot(_, slotID, itemID uint) error {
	if itemID == 0 {
		delete(m.Slot, slotID)
	} else {
		m.Slot[slotID] = itemID
	}
	return nil
}

type GroupRepo struct {
	UserGroups map[string]uint
}

func (m *GroupRepo) SetUserGroup(username string, groupID uint) error {
	m.UserGroups[username] = groupID
	return nil
}

func (m *GroupRepo) GetGroupMembers(groupID uint) ([]string, error) {
	members := make([]string, 0)
	for username, gid := range m.UserGroups {
		if gid == groupID {
			members = append(members, username)
		}
	}
	return members, nil
}

type QuestionRepo struct {
	Sessions  map[string]model.QuestionSession
	Created   string
	Questions map[uint]model.Question
	NextID    uint
}

func (m *QuestionRepo) CreateSession(groupID uint) (string, model.Question, error) {
	q := model.Question{Description: "What is six times three?", Answer: 1}
	id := "session-id"
	if m.Sessions == nil {
		m.Sessions = map[string]model.QuestionSession{}
	}
	m.Sessions[id] = model.QuestionSession{
		ExpiresAt: time.Now().Add(15 * time.Minute),
		GroupID:   groupID,
		Question:  q,
	}
	m.Created = id
	return id, q, nil
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
		records = append(records, model.QuestionRecord{ID: id, Description: q.Description, Answer: q.Answer})
	}
	return records, nil
}

func (m *QuestionRepo) SearchQuestions(query string) ([]model.QuestionRecord, error) {
	needle := strings.ToLower(query)
	records := make([]model.QuestionRecord, 0, len(m.Questions))
	for id, q := range m.Questions {
		if needle == "" || strings.Contains(strings.ToLower(q.Description), needle) {
			records = append(records, model.QuestionRecord{ID: id, Description: q.Description, Answer: q.Answer})
		}
	}
	sort.Slice(records, func(i, j int) bool { return records[i].ID < records[j].ID })
	return records, nil
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
