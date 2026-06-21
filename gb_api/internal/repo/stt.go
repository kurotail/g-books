package repo

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"gb-api/internal/config"
)

// STTRepo transcribes a spoken recording into text. It backs the voice_response
// grading flow: the student submits a base64-encoded WAV recording, the transcript is
// compared against the question's expected answer.
type STTRepo interface {
	Transcribe(wavB64 string) (string, error)
}

// sttRepo talks to the local Taigi STT HTTP service (see taigi_stt/README.md):
// POST {base}/transcribe with {"audio_b64": "..."} returns {"text": "..."}.
type sttRepo struct {
	baseURL string
	client  *http.Client
}

// transcribeRequest / transcribeResponse mirror the STT service's JSON contract.
type transcribeRequest struct {
	AudioB64 string `json:"audio_b64"`
}

type transcribeResponse struct {
	Text string `json:"text"`
}

func (r *sttRepo) Transcribe(wavB64 string) (string, error) {
	// Reject obviously bad input before hitting the network; the service expects
	// standard base64 and would just return a 400 anyway.
	if _, err := base64.StdEncoding.DecodeString(wavB64); err != nil {
		return "", err
	}

	body, err := json.Marshal(transcribeRequest{AudioB64: wavB64})
	if err != nil {
		return "", err
	}

	resp, err := r.client.Post(r.baseURL+"/transcribe", "application/json", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("stt service returned %d: %s", resp.StatusCode, strings.TrimSpace(string(respBody)))
	}

	var out transcribeResponse
	if err := json.Unmarshal(respBody, &out); err != nil {
		return "", err
	}
	return out.Text, nil
}

// InitSTTRepo builds the STT client pointed at the process-level config.STTBaseURL;
// the model can be slow on CPU so the timeout is generous.
func InitSTTRepo() STTRepo {
	return &sttRepo{
		baseURL: strings.TrimRight(config.STTBaseURL, "/"),
		client:  &http.Client{Timeout: 120 * time.Second},
	}
}
