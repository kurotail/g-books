// Package mock provides in-memory implementations of the repo interfaces for
// use in tests across the service and handler packages.
package mock

import (
	"maps"
	"sync"
	"time"

	apperr "gb-api/internal/error"
	"gb-api/internal/model"
	"gb-api/internal/repo"
)

var (
	_ repo.AuthRepo     = (*AuthRepo)(nil)
	_ repo.ItemRepo     = (*ItemRepo)(nil)
	_ repo.GroupRepo    = (*GroupRepo)(nil)
	_ repo.QuestionRepo = (*QuestionRepo)(nil)
)

// AuthRepo is an in-memory repo.AuthRepo.
type AuthRepo struct {
	Users         map[string]string
	Roles         map[string]uint
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

func (m *AuthRepo) GetAllUsers() ([]string, error) {
	users := make([]string, 0, len(m.Users))
	for username := range m.Users {
		users = append(users, username)
	}
	return users, nil
}

func (m *AuthRepo) GetRole(username string) (uint, error) {
	return m.Roles[username], nil
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

// ItemRepo is an in-memory repo.ItemRepo.
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

// GroupRepo is an in-memory repo.GroupRepo.
type GroupRepo struct {
	UserGroups map[string]uint
	Users      map[string]bool
	Roles      map[string]uint
}

func (m *GroupRepo) SetUserGroup(username string, groupID uint) error {
	m.UserGroups[username] = groupID
	return nil
}

func (m *GroupRepo) GetUserGroup(username string) (uint, bool, error) {
	groupID, ok := m.UserGroups[username]
	return groupID, ok, nil
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

func (m *GroupRepo) UserExists(username string) (bool, error) {
	return m.Users[username], nil
}

func (m *GroupRepo) GetRole(username string) (uint, error) {
	return m.Roles[username], nil
}

// QuestionRepo is an in-memory repo.QuestionRepo. Role is the role level
// reported for every user; Created records the last session id handed out.
type QuestionRepo struct {
	Role     uint
	Sessions map[string]model.QuestionSession
	Created  string
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

func (m *QuestionRepo) GetRole(_ string) (uint, error) {
	return m.Role, nil
}
