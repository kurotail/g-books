// Package apperr defines domain-level sentinel errors shared across layers.
package apperr

import "errors"

// ErrInsufficientStock is returned when a decrement would drop an item's
// inventory count below zero.
var ErrInsufficientStock = errors.New("庫存不足")
