# Taigi STT API

A local HTTP service that transcribes Taiwanese (Taigi) speech using the
[`NUTN-KWS/Whisper-Taiwanese-model-v0.5`](https://huggingface.co/NUTN-KWS/Whisper-Taiwanese-model-v0.5)
Whisper model. Send a base64-encoded WAV string, get back the transcribed text.

## Running the service

```bash
uv sync
uv run uvicorn app:app --host 127.0.0.1 --port 8964
```

The service binds to `127.0.0.1` (loopback) so it **only accepts requests from the local machine**.
Connections from other hosts on the network are refused by the OS. To expose it externally
(not recommended), change the host to `0.0.0.0`.

The model is loaded once at startup. On the first run it downloads the weights into `./model`;
subsequent runs load from that directory.

- **Hardware acceleration**: if a CUDA GPU is available, inference runs on `cuda:0` with `float16`.
  Otherwise it falls back to CPU (`float32`). No configuration needed.
- **Base URL**: `http://localhost:8964`

> While the server is running it locks the Torch DLLs, so `uv run` / `uv sync` cannot modify the
> virtual environment. Stop the server first, or use `.venv/Scripts/python.exe` directly, if you
> need to run scripts meanwhile.

## Endpoints

### `GET /health`

Liveness check.

**Response** `200 OK`

```json
{ "status": "ok" }
```

```bash
curl http://localhost:8964/health
```

---

### `POST /transcribe`

Transcribe a base64-encoded audio file.

**Request**

- Header: `Content-Type: application/json`
- Body:

| Field       | Type   | Required | Description                                              |
| ----------- | ------ | -------- | -------------------------------------------------------- |
| `audio_b64` | string | yes      | Base64-encoded audio bytes (WAV recommended; any format ffmpeg can decode works). |

```json
{ "audio_b64": "UklGR.... (base64 audio)" }
```

**Response** `200 OK`

```json
{ "text": "心肝寶貝" }
```

**Errors**

| Status | Condition                                | Body                                        |
| ------ | ---------------------------------------- | ------------------------------------------- |
| `400`  | `audio_b64` is not valid base64          | `{ "detail": "Invalid base64 audio" }`      |
| `400`  | Decoded audio is empty                   | `{ "detail": "Empty audio" }`               |
| `422`  | `audio_b64` field missing / wrong type   | FastAPI validation error                     |

## Examples

### curl

```bash
B64=$(base64 -w0 audio.wav)
curl -X POST http://localhost:8964/transcribe \
  -H "Content-Type: application/json" \
  -d "{\"audio_b64\": \"$B64\"}"
```

### Python

```python
import base64, requests

with open("audio.wav", "rb") as f:
    audio_b64 = base64.b64encode(f.read()).decode()

resp = requests.post(
    "http://localhost:8964/transcribe",
    json={"audio_b64": audio_b64},
)
print(resp.json()["text"])
```
