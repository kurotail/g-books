package repo

import (
	"context"

	"gb-api/internal/model"
)

// ScoreRepo computes the per-user leaderboard: the sum of question difficulty over the
// intact items sitting in each user's slots. Used to pre-calculate scores at QUIZ2 end.
type ScoreRepo interface {
	SlotDifficultySums() ([]model.UserScore, error)
}

type scoreRepo struct{}

// SlotDifficultySums returns one row per user (every user, score 0 when they hold no
// scoring items). Broken slots (negative item_id) are excluded; only intact items count.
func (_ *scoreRepo) SlotDifficultySums() ([]model.UserScore, error) {
	ctx := context.Background()
	rows, err := pool.Query(ctx,
		`SELECT u.id, COALESCE(SUM(q.difficulty), 0)::bigint AS score
		 FROM users u
		 LEFT JOIN user_slots us ON us.user_id = u.id AND us.item_id > 0
		 LEFT JOIN items i       ON i.id = us.item_id
		 LEFT JOIN questions q   ON q.id = i.question_id
		 GROUP BY u.id
		 ORDER BY u.id`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]model.UserScore, 0)
	for rows.Next() {
		var sc model.UserScore
		if err := rows.Scan(&sc.UserID, &sc.Score); err != nil {
			return nil, err
		}
		out = append(out, sc)
	}
	return out, rows.Err()
}

func InitScoreRepo() ScoreRepo {
	return &scoreRepo{}
}
