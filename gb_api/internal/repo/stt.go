package repo

import "encoding/base64"

// STTRepo transcribes a spoken recording into text. It backs the voice_response
// grading flow: the student submits a base64-encoded WAV recording, the transcript is
// compared against the question's expected answer.
type STTRepo interface {
	Transcribe(wavB64 string) (string, error)
}

// sttRepo is a placeholder implementation: it validates that the input is base64 and
// returns an empty transcript. Swap this for a real speech-to-text API call that
// decodes and transcribes the WAV audio.
type sttRepo struct{}

func (_ *sttRepo) Transcribe(wavB64 string) (string, error) {
	if _, err := base64.StdEncoding.DecodeString(wavB64); err != nil {
		return "", err
	}
	return "", nil
}

func InitSTTRepo() STTRepo {
	return &sttRepo{}
}
