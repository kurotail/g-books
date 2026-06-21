// Read a WAV file, base64-encode it, and run it through the STT repo against
// the live Taigi STT service (see taigi_stt/README.md). Start the service first:
//
//	cd taigi_stt && uv run uvicorn app:app --host 127.0.0.1 --port 8964
//
// then from the repo root:
//
//	go run ./cmd/stt            # uses taigi_stt/audio.wav
//	go run ./cmd/stt path/to/other.wav
//
// Point at a non-default service with STT_BASE_URL (e.g. http://localhost:8964).
package main

import (
	"encoding/base64"
	"fmt"
	"os"

	"gb-api/internal/repo"
)

func main() {
	path := "taigi_stt/audio.wav"
	if len(os.Args) > 1 {
		path = os.Args[1]
	}

	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "read %s: %v\n", path, err)
		os.Exit(1)
	}
	fmt.Printf("read %s (%d bytes)\n", path, len(data))

	b64 := base64.StdEncoding.EncodeToString(data)

	stt := repo.InitSTTRepo()
	text, err := stt.Transcribe(b64)
	if err != nil {
		fmt.Fprintf(os.Stderr, "transcribe: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("transcript: %s\n", text)
}
