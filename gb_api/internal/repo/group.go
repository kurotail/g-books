package repo

import (
	"fmt"
	"sort"

	apperr "gb-api/internal/error"
	"gb-api/internal/model"
)

type GroupRepo interface {
	SetUserGroup(username string, groupID uint) error
	GetGroup(groupID uint) (model.Group, error)
	SetGroupName(groupID uint, name string) error
	SetBuildingID(groupID uint, buildingID uint) error
	SetGroupProfilePic(groupID uint, url string) error
	DeleteGroup(groupID uint) (bool, error)
}

type groupRepo struct{}

// defaultGroupName is used when a group has no name set.
func defaultGroupName(groupID uint) string {
	return fmt.Sprintf("Group %d", groupID)
}

// newGroup returns an empty group row with its maps initialized.
func newGroup(id uint) *Group {
	return &Group{
		ID:        id,
		Inventory: map[uint]struct{}{},
		Slots:     map[uint]int{},
		Members:   map[string]struct{}{},
	}
}

// SetUserGroup moves a user between groups, keeping both the user's GroupID and the
// groups' member sets in sync. A groupID of 0 removes the user from any group.
func (_ *groupRepo) SetUserGroup(username string, groupID uint) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	u := db.users[username]
	if u == nil {
		return nil
	}
	if u.GroupID != 0 {
		if old := db.groups[u.GroupID]; old != nil {
			delete(old.Members, username)
		}
	}
	u.GroupID = groupID
	if groupID != 0 {
		g := db.groups[groupID]
		if g == nil {
			g = newGroup(groupID)
			db.groups[groupID] = g
		}
		g.Members[username] = struct{}{}
	}
	return nil
}

func (_ *groupRepo) GetGroup(groupID uint) (model.Group, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	g := db.groups[groupID]
	if g == nil {
		return model.Group{}, apperr.ErrGroupNotFound
	}
	members := make([]string, 0, len(g.Members))
	for username := range g.Members {
		members = append(members, username)
	}
	sort.Strings(members)
	name := defaultGroupName(groupID)
	if g.Name != "" {
		name = g.Name
	}
	return model.Group{ID: groupID, Name: name, BuildingID: g.BuildingID, Members: members, ProfilePicURL: g.ProfilePicURL}, nil
}

func (_ *groupRepo) SetGroupName(groupID uint, name string) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	g := db.groups[groupID]
	if g == nil {
		g = newGroup(groupID)
		db.groups[groupID] = g
	}
	g.Name = name
	return nil
}

func (_ *groupRepo) SetBuildingID(groupID uint, buildingID uint) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	g := db.groups[groupID]
	if g == nil {
		g = newGroup(groupID)
		db.groups[groupID] = g
	}
	g.BuildingID = buildingID
	return nil
}

func (_ *groupRepo) SetGroupProfilePic(groupID uint, url string) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	g := db.groups[groupID]
	if g == nil {
		g = newGroup(groupID)
		db.groups[groupID] = g
	}
	g.ProfilePicURL = url
	return nil
}

// DeleteGroup removes a group and clears the membership of any users that belonged to it.
func (_ *groupRepo) DeleteGroup(groupID uint) (bool, error) {
	db.mu.Lock()
	defer db.mu.Unlock()
	g := db.groups[groupID]
	if g == nil {
		return false, nil
	}
	for username := range g.Members {
		if u := db.users[username]; u != nil {
			u.GroupID = 0
		}
	}
	delete(db.groups, groupID)
	return true, nil
}

func InitGroupRepo() GroupRepo {
	return &groupRepo{}
}
