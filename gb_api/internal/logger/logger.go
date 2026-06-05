// Package logger provides the application's process-wide structured logger.
// During `go test` runs it discards all output so test logs stay clean;
// otherwise it writes human-readable text to stdout in the form:
//
//	2026-06-05T13:42:51.011+08:00 INFO GET /api/users status=401 duration=0s
package logger

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
)

// L is the process-wide logger. It is silent when running under `go test`.
var L = newLogger()

func newLogger() *slog.Logger {
	var w io.Writer = os.Stdout
	if testing.Testing() {
		w = io.Discard
	}
	return slog.New(&textHandler{w: w, level: slog.LevelInfo, mu: &sync.Mutex{}})
}

// textHandler is a minimal slog.Handler that renders each record as:
//
//	<timestamp> <LEVEL> <message> key=value key=value
//
// with the timestamp in RFC3339 form down to milliseconds.
type textHandler struct {
	w     io.Writer
	level slog.Leveler
	mu    *sync.Mutex
}

func (h *textHandler) Enabled(_ context.Context, level slog.Level) bool {
	return level >= h.level.Level()
}

func (h *textHandler) Handle(_ context.Context, r slog.Record) error {
	var b strings.Builder
	b.WriteString(r.Time.Format("2006-01-02T15:04:05.000Z07:00"))
	b.WriteByte(' ')
	b.WriteString(r.Level.String())
	b.WriteByte(' ')
	b.WriteString(r.Message)
	r.Attrs(func(a slog.Attr) bool {
		b.WriteByte(' ')
		b.WriteString(a.Key)
		b.WriteByte('=')
		b.WriteString(a.Value.String())
		return true
	})
	b.WriteByte('\n')

	h.mu.Lock()
	defer h.mu.Unlock()
	_, err := io.WriteString(h.w, b.String())
	return err
}

func (h *textHandler) WithAttrs([]slog.Attr) slog.Handler { return h }
func (h *textHandler) WithGroup(string) slog.Handler      { return h }

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Unwrap() http.ResponseWriter { return r.ResponseWriter }

func RequestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		L.Info(r.Method+" "+r.URL.Path,
			"status", rec.status,
			"duration", time.Since(start),
		)
	})
}
