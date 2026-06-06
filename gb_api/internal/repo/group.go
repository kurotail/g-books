package repo

type GroupRepo interface {
	SetUserGroup(username string, groupID uint) error
	GetUserGroup(username string) (uint, bool, error)
	GetGroupMembers(groupID uint) ([]string, error)
}

type groupRepo struct{}

func (_ *groupRepo) SetUserGroup(username string, groupID uint) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	if u := db.users[username]; u != nil {
		u.GroupID = &groupID
	}
	return nil
}

func (_ *groupRepo) GetUserGroup(username string) (uint, bool, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	u := db.users[username]
	if u == nil || u.GroupID == nil {
		return 0, false, nil
	}
	return *u.GroupID, true, nil
}

func (_ *groupRepo) GetGroupMembers(groupID uint) ([]string, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	members := make([]string, 0)
	for username, u := range db.users {
		if u.GroupID != nil && *u.GroupID == groupID {
			members = append(members, username)
		}
	}
	return members, nil
}

func InitGroupRepo() GroupRepo {
	return &groupRepo{}
}
