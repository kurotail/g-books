// Package mock provides in-memory implementations of the repo interfaces for
// use in tests across the service and handler packages.
package mock

import (
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
	_ repo.InventoryRepo    = (*ItemRepo)(nil)
	_ repo.BuildingRepo     = (*BuildingRepo)(nil)
	_ repo.StudentRepo      = (*StudentRepo)(nil)
	_ repo.QuestionRepo     = (*QuestionRepo)(nil)
	_ repo.STTRepo          = (*STTRepo)(nil)
)

// Process-wide username<->id registry. The real DB keys child rows on a numeric
// id, while fixtures here are written in terms of usernames. Because tests mint a
// token in one mock instance (a throwaway AuthSvc) and resolve it in another (the
// service under test), the username->id mapping must be shared across instances —
// so it lives at package scope. ids are opaque (never asserted), only consistency
// matters.
var (
	regMu    sync.Mutex
	regIDs   = map[string]uint{}
	regNames = map[uint]string{}
	regNext  uint
)

// IDFor returns username's stable numeric id, assigning one on first use. Exported
// for test helpers that mint a token for a username.
func IDFor(username string) uint {
	regMu.Lock()
	defer regMu.Unlock()
	return regIDForLocked(username)
}

func regIDForLocked(username string) uint {
	if id, ok := regIDs[username]; ok {
		return id
	}
	regNext++
	id := regNext
	regIDs[username] = id
	regNames[id] = username
	return id
}

// regNameOf returns the username currently mapped to id (registry-only; liveness
// is checked separately against an instance's user set).
func regNameOf(id uint) (string, bool) {
	regMu.Lock()
	defer regMu.Unlock()
	name, ok := regNames[id]
	return name, ok
}

type AuthRepo struct {
	Users         map[string]string
	Roles         map[string]uint
	Buildings     map[string]uint // username -> building; absent/0 = no building
	Pics          map[string]string
	DisplayNames  map[string]string // username -> display name; absent = falls back to username
	Students      map[string][]uint // username -> assigned student ids
	RefreshTokens sync.Map
}

// idFor returns username's stable numeric id from the shared registry.
func (m *AuthRepo) idFor(username string) uint {
	return IDFor(username)
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

func (m *AuthRepo) GetUserByUsername(username string) (model.User, error) {
	if _, ok := m.Roles[username]; !ok {
		return model.User{}, apperr.ErrUserNotFound
	}
	return m.buildUser(username), nil
}

func (m *AuthRepo) GetUserByID(id uint) (model.User, error) {
	username, err := m.nameFor(id)
	if err != nil {
		return model.User{}, err
	}
	return m.buildUser(username), nil
}

func (m *AuthRepo) buildUser(username string) model.User {
	displayName, ok := m.DisplayNames[username]
	if !ok {
		displayName = username // matches the init-to-username default
	}
	return model.User{ID: m.idFor(username), Username: username, DisplayName: displayName, Role: m.Roles[username], BuildingID: m.Buildings[username], ProfilePicURL: m.Pics[username], Students: m.Students[username]}
}

// nameFor resolves a numeric id back to its username, returning ErrUserNotFound
// when no live user in this instance holds it.
func (m *AuthRepo) nameFor(id uint) (string, error) {
	username, ok := regNameOf(id)
	if !ok {
		return "", apperr.ErrUserNotFound
	}
	if _, live := m.Roles[username]; !live {
		return "", apperr.ErrUserNotFound
	}
	return username, nil
}

func (m *AuthRepo) SetUserStudents(id uint, studentIDs []uint) error {
	username, err := m.nameFor(id)
	if err != nil {
		return err
	}
	if m.Students == nil {
		m.Students = map[string][]uint{}
	}
	m.Students[username] = studentIDs
	return nil
}

func (m *AuthRepo) SetUserProfilePic(id uint, url string) error {
	username, err := m.nameFor(id)
	if err != nil {
		return err
	}
	if m.Pics == nil {
		m.Pics = map[string]string{}
	}
	m.Pics[username] = url
	return nil
}

func (m *AuthRepo) SetUserBuilding(id uint, buildingID uint) error {
	username, err := m.nameFor(id)
	if err != nil {
		return err
	}
	if m.Buildings == nil {
		m.Buildings = map[string]uint{}
	}
	m.Buildings[username] = buildingID
	return nil
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

func (m *AuthRepo) SetUserPassword(id uint, plainPassword string) error {
	username, err := m.nameFor(id)
	if err != nil {
		return err
	}
	if m.Users == nil {
		m.Users = map[string]string{}
	}
	m.Users[username] = plainPassword
	return nil
}

// SetUserDisplayName updates a user's mutable display name, keyed by its immutable id.
func (m *AuthRepo) SetUserDisplayName(id uint, displayName string) error {
	username, err := m.nameFor(id)
	if err != nil {
		return err
	}
	if m.DisplayNames == nil {
		m.DisplayNames = map[string]string{}
	}
	m.DisplayNames[username] = displayName
	return nil
}

func (m *AuthRepo) DeleteUser(id uint) (bool, error) {
	username, err := m.nameFor(id)
	if err != nil {
		return false, nil
	}
	// Clear only this instance's user state; leave the shared registry mapping
	// (other instances/tests may use the same username, and liveness is checked
	// against Roles via nameFor).
	delete(m.Users, username)
	delete(m.Roles, username)
	delete(m.Buildings, username)
	delete(m.Pics, username)
	return true, nil
}

type RoleRepo struct {
	Role uint
}

func (m *RoleRepo) ValidateCredentials(_, _ string) (bool, error) { return false, nil }
func (m *RoleRepo) GetAllUsers() ([]model.User, error)            { return nil, nil }
func (m *RoleRepo) GetUserByUsername(username string) (model.User, error) {
	return model.User{ID: IDFor(username), Username: username, Role: m.Role}, nil
}
func (m *RoleRepo) GetUserByID(id uint) (model.User, error) {
	name, _ := regNameOf(id)
	return model.User{ID: id, Username: name, Role: m.Role}, nil
}
func (m *RoleRepo) CreateUser(_, _ string, _ uint) error      { return nil }
func (m *RoleRepo) SetUserProfilePic(_ uint, _ string) error  { return nil }
func (m *RoleRepo) SetUserBuilding(_ uint, _ uint) error      { return nil }
func (m *RoleRepo) SetUserStudents(_ uint, _ []uint) error    { return nil }
func (m *RoleRepo) SetUserPassword(_ uint, _ string) error    { return nil }
func (m *RoleRepo) SetUserDisplayName(_ uint, _ string) error { return nil }
func (m *RoleRepo) DeleteUser(_ uint) (bool, error)           { return true, nil }

type ItemRepo struct {
	Inv          map[uint]struct{}    // owned (unslotted) item ids
	Slot         map[uint]int         // slot_id -> signed item_id
	Items        map[uint]model.Item  // item table
	NextItemID   uint                 // next id assigned by CreateItem
	AttackBlocks map[[3]uint]struct{} // {ownerID, slotID, attackerID} barred from re-attacking
}

func (m *ItemRepo) QueryInventory(_ uint) ([]model.Item, error) {
	ids := make([]uint, 0, len(m.Inv))
	for id := range m.Inv {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	items := make([]model.Item, 0, len(ids))
	for _, id := range ids {
		if it, ok := m.Items[id]; ok { // mirror the INNER JOIN: skip orphans
			items = append(items, it)
		}
	}
	return items, nil
}

func (m *ItemRepo) QuerySlotItems(_ uint) (map[uint]model.SlotItem, error) {
	out := make(map[uint]model.SlotItem, len(m.Slot))
	for slotID, signed := range m.Slot {
		if signed == 0 {
			continue
		}
		broken := signed < 0
		itemID := uint(signed)
		if broken {
			itemID = uint(-signed)
		}
		if it, ok := m.Items[itemID]; ok {
			out[slotID] = model.SlotItem{Item: it, Broken: broken}
		}
	}
	return out, nil
}

func (m *ItemRepo) QuerySlot(_ uint) (map[uint]int, error) {
	result := make(map[uint]int, len(m.Slot))
	maps.Copy(result, m.Slot)
	return result, nil
}

func (m *ItemRepo) OwnedItem(_ uint, itemID uint) (model.Item, bool, error) {
	if _, owned := m.Inv[itemID]; !owned {
		return model.Item{}, false, nil
	}
	it, ok := m.Items[itemID]
	return it, ok, nil
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

func (m *ItemRepo) SetItemQuestion(itemID, questionID uint) error {
	if it, ok := m.Items[itemID]; ok {
		it.QuestionID = questionID
		m.Items[itemID] = it
	}
	return nil
}

func (m *ItemRepo) AddInvItem(_ uint, itemID uint) error {
	if m.Inv == nil {
		m.Inv = map[uint]struct{}{}
	}
	m.Inv[itemID] = struct{}{}
	return nil
}

func (m *ItemRepo) RemoveInvItem(_ uint, itemID uint) error {
	delete(m.Inv, itemID)
	return nil
}

func (m *ItemRepo) SetSlot(_ uint, slotID uint, itemID int) error {
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

func (m *ItemRepo) IsAttackBlocked(ownerID, slotID, attackerID uint) (bool, error) {
	_, ok := m.AttackBlocks[[3]uint{ownerID, slotID, attackerID}]
	return ok, nil
}

func (m *ItemRepo) AddAttackBlock(ownerID, slotID, attackerID uint) error {
	if m.AttackBlocks == nil {
		m.AttackBlocks = map[[3]uint]struct{}{}
	}
	m.AttackBlocks[[3]uint{ownerID, slotID, attackerID}] = struct{}{}
	return nil
}

func (m *ItemRepo) ClearAttackBlocks(ownerID, slotID uint) error {
	for k := range m.AttackBlocks {
		if k[0] == ownerID && k[1] == slotID {
			delete(m.AttackBlocks, k)
		}
	}
	return nil
}

func (m *ItemRepo) ClearAllAttackBlocks() error {
	m.AttackBlocks = nil
	return nil
}

func (m *ItemRepo) QuerySlotBlocks(ownerID uint) (map[uint][]uint, error) {
	out := make(map[uint][]uint)
	for k := range m.AttackBlocks {
		if k[0] == ownerID {
			out[k[1]] = append(out[k[1]], k[2])
		}
	}
	for _, ids := range out {
		sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	}
	return out, nil
}

// ScoreRepo is a stub ScoreRepo whose SlotDifficultySums returns the preset Sums.
type ScoreRepo struct {
	Sums []model.UserScore
	Err  error
}

func (m *ScoreRepo) SlotDifficultySums() ([]model.UserScore, error) {
	return m.Sums, m.Err
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

type StudentRepo struct {
	Students map[uint]model.Student
	NextID   uint
}

func (m *StudentRepo) CreateStudent(name, profilePicURL string) (model.Student, error) {
	if m.Students == nil {
		m.Students = map[uint]model.Student{}
	}
	if m.NextID == 0 {
		m.NextID = 1000 // high base to avoid colliding with test-seeded ids
	}
	id := m.NextID
	m.NextID++
	st := model.Student{StudentID: id, Name: name, ProfilePicURL: profilePicURL}
	m.Students[id] = st
	return st, nil
}

func (m *StudentRepo) UpdateStudent(id uint, name, profilePicURL string) (model.Student, error) {
	if _, ok := m.Students[id]; !ok {
		return model.Student{}, apperr.ErrStudentNotFound
	}
	st := model.Student{StudentID: id, Name: name, ProfilePicURL: profilePicURL}
	m.Students[id] = st
	return st, nil
}

func (m *StudentRepo) GetStudent(id uint) (model.Student, error) {
	s, ok := m.Students[id]
	if !ok {
		return model.Student{}, apperr.ErrStudentNotFound
	}
	return s, nil
}

func (m *StudentRepo) ExistingStudentIDs(ids []uint) (map[uint]bool, error) {
	out := make(map[uint]bool, len(ids))
	for _, id := range ids {
		if _, ok := m.Students[id]; ok {
			out[id] = true
		}
	}
	return out, nil
}

func (m *StudentRepo) GetAllStudents() ([]model.Student, error) {
	out := make([]model.Student, 0, len(m.Students))
	for _, s := range m.Students {
		out = append(out, s)
	}
	return out, nil
}

func (m *StudentRepo) DeleteStudent(id uint) error {
	if _, ok := m.Students[id]; !ok {
		return apperr.ErrStudentNotFound
	}
	delete(m.Students, id)
	return nil
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
