package repo

type GroupRepo interface {
	SetUserGroup(username string, groupID uint) error
	GetGroupMembers(groupID uint) ([]string, error)
}

type groupRepo struct{}

func (_ *groupRepo) SetUserGroup(username string, groupID uint) error {
	db.mu.Lock()
	defer db.mu.Unlock()
	if u := db.users[username]; u != nil {
		u.GroupID = groupID
	}
	return nil
}

func (_ *groupRepo) GetGroupMembers(groupID uint) ([]string, error) {
	db.mu.RLock()
	defer db.mu.RUnlock()
	members := make([]string, 0)
	for username, u := range db.users {
		if u.GroupID == groupID {
			members = append(members, username)
		}
	}
	return members, nil
}

func InitGroupRepo() GroupRepo {
	return &groupRepo{}
}
