package repo

import (
	"fmt"

	"gb-api/internal/model"
)

type GroupRepo interface {
	SetUserGroup(username string, groupID uint) error
	GetGroup(groupID uint) (model.Group, error)
	SetGroupName(groupID uint, name string) error
	SetBuildingID(groupID uint, buildingID uint) error
}

type groupRepo struct{}

// defaultGroupName is used when a group has no name set.
func defaultGroupName(groupID uint) string {
	return fmt.Sprintf("Group %d", groupID)
}

func (_ *groupRepo) SetUserGroup(username string, groupID uint) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	if u := db.users[username]; u != nil {
		u.GroupID = groupID
	}
	return nil
}

func (_ *groupRepo) GetGroup(groupID uint) (model.Group, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	members := make([]string, 0)
	for username, u := range db.users {
		if u.GroupID == groupID {
			members = append(members, username)
		}
	}
	name := defaultGroupName(groupID)
	var buildingID uint
	if g := db.groups[groupID]; g != nil {
		if g.Name != "" {
			name = g.Name
		}
		buildingID = g.BuildingID
	}
	return model.Group{ID: groupID, Name: name, BuildingID: buildingID, Members: members}, nil
}

func (_ *groupRepo) SetGroupName(groupID uint, name string) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	g := db.groups[groupID]
	if g == nil {
		g = &Group{ID: groupID, Inventory: map[uint]uint{}, Slots: map[uint]int{}}
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
		g = &Group{ID: groupID, Inventory: map[uint]uint{}, Slots: map[uint]int{}}
		db.groups[groupID] = g
	}
	g.BuildingID = buildingID
	return nil
}

func InitGroupRepo() GroupRepo {
	return &groupRepo{}
}
