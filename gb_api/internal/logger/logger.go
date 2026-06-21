// Package logger provides the application's process-wide structured logger.
// During `go test` runs it discards all output so test logs stay clean;
// otherwise it writes human-readable text to stdout in the form:
//
//	2026-06-05T13:42:51.011+08:00 INFO GET /api/users status=401 duration=0s
package logger

import (
	"bytes"
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

// maxBodyLog caps how many bytes of a request body we render at DEBUG so a
// large payload can't flood the logs.
const maxBodyLog = 4 << 10

// L is the process-wide logger. It is silent when running under `go test`.
var L = newLogger()

func newLogger() *slog.Logger {
	var w io.Writer = os.Stdout
	if testing.Testing() {
		w = io.Discard
	}
	return slog.New(&textHandler{w: w, level: levelFromEnv(), mu: &sync.Mutex{}})
}

// levelFromEnv reads LOG_LEVEL (debug|info|warn|error), defaulting to info.
func levelFromEnv() slog.Level {
	switch strings.ToLower(os.Getenv("LOG_LEVEL")) {
	case "debug":
		return slog.LevelDebug
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
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

// logBody renders the request body at DEBUG, then restores it so the handler
// can still read it. Multipart uploads are skipped to keep binary media out of
// the logs, and the rendered text is capped at maxBodyLog bytes.
func logBody(r *http.Request) {
	if !L.Enabled(r.Context(), slog.LevelDebug) || r.Body == nil {
		return
	}
	if ct := r.Header.Get("Content-Type"); strings.HasPrefix(ct, "multipart/form-data") {
		return
	}
	body, err := io.ReadAll(r.Body)
	if err != nil {
		return
	}
	r.Body = io.NopCloser(bytes.NewReader(body))
	rendered := body
	if len(rendered) > maxBodyLog {
		rendered = rendered[:maxBodyLog]
	}
	L.Debug(r.Method+" "+r.URL.Path+" body", "bytes", len(body), "body", string(rendered))
}

func RequestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		logBody(r)
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		L.Info(r.Method+" "+r.URL.Path,
			"status", rec.status,
			"duration", time.Since(start),
		)
	})
}
