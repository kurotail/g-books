package repo

import "sync"

type GroupRepo interface {
	SetUserGroup(username string, groupID uint) error
	GetUserGroup(username string) (uint, bool, error)
	GetGroupMembers(groupID uint) ([]string, error)
	UserExists(username string) (bool, error)
	GetRole(username string) (uint, error)
}

type groupRepo struct{}

var groupMu sync.RWMutex

func (_ *groupRepo) SetUserGroup(username string, groupID uint) error {
	groupMu.Lock()
	defer groupMu.Unlock()
	mem_db.userGroups[username] = groupID
	return nil
}

func (_ *groupRepo) GetUserGroup(username string) (uint, bool, error) {
	groupMu.RLock()
	defer groupMu.RUnlock()
	groupID, ok := mem_db.userGroups[username]
	return groupID, ok, nil
}

func (_ *groupRepo) GetGroupMembers(groupID uint) ([]string, error) {
	groupMu.RLock()
	defer groupMu.RUnlock()
	members := make([]string, 0)
	for username, gid := range mem_db.userGroups {
		if gid == groupID {
			members = append(members, username)
		}
	}
	return members, nil
}

func (_ *groupRepo) UserExists(username string) (bool, error) {
	_, ok := mem_db.users[username]
	return ok, nil
}

func (_ *groupRepo) GetRole(username string) (uint, error) {
	return mem_db.roles[username], nil
}

func InitGroupRepo() GroupRepo {
	return &groupRepo{}
}
