import base64
import binascii
from pathlib import Path

import torch
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from transformers import AutoProcessor, AutoModelForSpeechSeq2Seq, pipeline

model_id = "NUTN-KWS/Whisper-Taiwanese-model-v0.5"
local_dir = Path("./model")


def download_model():
    """Download the model + processor from the Hub into ./model."""
    print(f"Downloading {model_id} -> {local_dir} ...")
    processor = AutoProcessor.from_pretrained(model_id)
    model = AutoModelForSpeechSeq2Seq.from_pretrained(model_id)
    model.save_pretrained(local_dir)
    processor.save_pretrained(local_dir)
    return model, processor


def load_model():
    """Load the model + processor from ./model, downloading first if needed."""
    if not (local_dir / "preprocessor_config.json").exists():
        return download_model()

    print(f"Loading model from {local_dir} ...")
    processor = AutoProcessor.from_pretrained(local_dir)
    model = AutoModelForSpeechSeq2Seq.from_pretrained(local_dir)
    return model, processor

app = FastAPI(title="Taigi STT")

_pipe = None


def get_pipe():
    """Build the ASR pipeline once and cache it."""
    global _pipe
    if _pipe is None:
        model, processor = load_model()
        # Use the GPU with half precision when CUDA is available, else CPU.
        use_cuda = torch.cuda.is_available()
        device = 0 if use_cuda else -1
        torch_dtype = torch.float16 if use_cuda else torch.float32
        print(f"Building pipeline on {'cuda:0' if use_cuda else 'cpu'} (dtype={torch_dtype})")
        _pipe = pipeline(
            "automatic-speech-recognition",
            model=model,
            tokenizer=processor.tokenizer,
            feature_extractor=processor.feature_extractor,
            device=device,
            torch_dtype=torch_dtype,
        )
    return _pipe


@app.on_event("startup")
def startup():
    # Load the model at startup so the first request isn't slow.
    get_pipe()


class TranscribeRequest(BaseModel):
    audio_b64: str


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/transcribe")
def transcribe(req: TranscribeRequest):
    try:
        audio_bytes = base64.b64decode(req.audio_b64, validate=True)
    except (binascii.Error, ValueError):
        raise HTTPException(status_code=400, detail="Invalid base64 audio")

    if not audio_bytes:
        raise HTTPException(status_code=400, detail="Empty audio")

    result = get_pipe()(
        audio_bytes,
        generate_kwargs={"language": "zh", "task": "transcribe"},
    )
    return {"text": result["text"]}
