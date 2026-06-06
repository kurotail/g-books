// Package apperr defines domain-level sentinel errors shared across layers.
package apperr

import "errors"

// ErrInsufficientStock is returned when a decrement would drop an item's
// inventory count below zero.
var ErrInsufficientStock = errors.New("庫存不足")

// ErrUserExists is returned when creating a user whose username is already taken.
var ErrUserExists = errors.New("使用者已存在")

// ErrNoQuestions is returned when a question session is requested but the pool
// is empty (e.g. a teacher deleted every question).
var ErrNoQuestions = errors.New("題庫為空")

// ErrUserNotFound is returned when a lookup targets a user that does not exist.
var ErrUserNotFound = errors.New("使用者不存在")
