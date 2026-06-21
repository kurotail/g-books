// Read a WAV file, base64-encode it, and transcribe it through the running gb-api
// server's POST /api/stt endpoint (Teacher/Admin only). Start the API server first
// (which in turn talks to the Taigi STT service, see taigi_stt/README.md), then from
// the repo root:
//
//	go run ./cmd/stt            # uses taigi_stt/audio.wav
//	go run ./cmd/stt path/to/other.wav
//
// The CLI logs in with ADMIN_USERNAME / ADMIN_PASSWORD (default admin / admin123) to
// obtain an access token. Point at a non-default server with STT_API_BASE_URL (default
// https://localhost, reached through nginx); TLS verification is skipped so a
// self-signed dev certificate is accepted.
package main

import (
	"bytes"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

func getenv(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}

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

	base := strings.TrimRight(getenv("STT_API_BASE_URL", "https://localhost"), "/")
	// Skip TLS verification so a self-signed dev certificate (nginx) is accepted; the
	// STT model can be slow on CPU, so allow a generous client timeout.
	client := &http.Client{
		Timeout: 150 * time.Second,
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
	}

	token, err := login(client, base)
	if err != nil {
		fmt.Fprintf(os.Stderr, "login: %v\n", err)
		os.Exit(1)
	}

	text, err := transcribe(client, base, token, b64)
	if err != nil {
		fmt.Fprintf(os.Stderr, "transcribe: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("transcript: %s\n", text)
}

// login exchanges the admin credentials for an access token via POST /api/login.
func login(client *http.Client, base string) (string, error) {
	body, _ := json.Marshal(map[string]string{
		"username": getenv("ADMIN_USERNAME", "admin"),
		"password": getenv("ADMIN_PASSWORD", "admin123"),
	})
	resp, err := client.Post(base+"/api/login", "application/json", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("/api/login returned %d: %s", resp.StatusCode, strings.TrimSpace(string(respBody)))
	}
	var out struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.Unmarshal(respBody, &out); err != nil {
		return "", err
	}
	if out.AccessToken == "" {
		return "", fmt.Errorf("no access_token in login response")
	}
	return out.AccessToken, nil
}

// transcribe POSTs the base64-encoded WAV to /api/stt and returns the recognized text.
func transcribe(client *http.Client, base, token, wavB64 string) (string, error) {
	body, _ := json.Marshal(map[string]string{"audio_b64": wavB64})
	r, err := http.NewRequest("POST", base+"/api/stt", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("Authorization", "Bearer "+token)

	resp, err := client.Do(r)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("/api/stt returned %d: %s", resp.StatusCode, strings.TrimSpace(string(respBody)))
	}
	var out struct {
		Text string `json:"text"`
	}
	if err := json.Unmarshal(respBody, &out); err != nil {
		return "", err
	}
	return out.Text, nil
}
