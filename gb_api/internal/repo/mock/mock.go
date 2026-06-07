// Package mock provides in-memory implementations of the repo interfaces for
// use in tests across the service and handler packages.
package mock

import (
	"fmt"
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
	_ repo.BuildingRepo     = (*BuildingRepo)(nil)
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
	return model.User{Username: username, Role: m.Roles[username], GroupID: m.Groups[username]}
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

type RoleRepo struct {
	Role uint
}

func (m *RoleRepo) ValidateCredentials(_, _ string) (bool, error) { return false, nil }
func (m *RoleRepo) GetAllUsers() ([]model.User, error)            { return nil, nil }
func (m *RoleRepo) GetUser(username string) (model.User, error) {
	return model.User{Username: username, Role: m.Role}, nil
}
func (m *RoleRepo) CreateUser(_, _ string, _, _ uint) error { return nil }

type ItemRepo struct {
	Inv   map[uint]struct{}   // owned (unslotted) item ids
	Slot  map[uint]int        // slot_id -> signed item_id
	Items map[uint]model.Item // item table
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
	name := fmt.Sprintf("Group %d", groupID)
	if n, ok := m.Names[groupID]; ok && n != "" {
		name = n
	}
	return model.Group{ID: groupID, Name: name, BuildingID: m.BuildingIDs[groupID], Members: members}, nil
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

type BuildingRepo struct {
	Buildings map[uint]model.Building
	NextID    uint
}

func (m *BuildingRepo) CreateBuilding(name, layout string, itemAllowedSlot map[uint][]uint, itemDifficulty map[uint]uint) (uint, error) {
	if m.Buildings == nil {
		m.Buildings = map[uint]model.Building{}
	}
	if m.NextID == 0 {
		m.NextID = 1
	}
	id := m.NextID
	m.NextID++
	m.Buildings[id] = model.Building{ID: id, Name: name, Layout: layout, TypeAllowedSlot: itemAllowedSlot, TypeDifficulty: itemDifficulty}
	return id, nil
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
		records = append(records, mockRecord(id, q))
	}
	return records, nil
}

func (m *QuestionRepo) SearchQuestions(query string, difficulty, area *uint) ([]model.QuestionRecord, error) {
	needle := strings.ToLower(query)
	records := make([]model.QuestionRecord, 0, len(m.Questions))
	for id, q := range m.Questions {
		if needle != "" && !strings.Contains(strings.ToLower(q.Description), needle) {
			continue
		}
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
		ID:          id,
		Description: q.Description,
		Answer:      q.Answer,
		Difficulty:  q.Difficulty,
		Area:        q.Area,
	}
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
