import sys
import threading
import time
import os
import numpy as np
import config
from transcribe.backends import (
    DEFAULT_QWEN_MODEL,
    DEFAULT_WHISPER_MODEL,
    create_backend,
)

_model_lock = threading.Lock()
_backend = None
_backend_name = None
_backend_model_repo = None
_last_used: float = 0.0
_unload_timer: threading.Timer | None = None
_ready = threading.Event()

IDLE_TIMEOUT = 120  # seconds before unloading model


def _log(msg):
    print(msg, flush=True)
    sys.stdout.flush()


def _resolve_backend_settings() -> tuple[str, str]:
    cfg = config.load()
    backend_name = os.environ.get("MUESLI_STT_BACKEND") or cfg.get("stt_backend") or "whisper"
    model_override = os.environ.get("MUESLI_STT_MODEL")

    if backend_name == "whisper":
        model_repo = model_override or cfg.get("stt_model") or cfg.get("whisper_model") or DEFAULT_WHISPER_MODEL
    elif backend_name == "qwen":
        model_repo = model_override or cfg.get("stt_model") or DEFAULT_QWEN_MODEL
    else:
        raise ValueError(f"Unsupported STT backend: {backend_name}")

    return backend_name, model_repo


def _ensure_loaded():
    global _backend, _backend_name, _backend_model_repo, _last_used
    with _model_lock:
        backend_name, model_repo = _resolve_backend_settings()
        if (
            _backend is None
            or _backend_name != backend_name
            or _backend_model_repo != model_repo
        ):
            _log(f"[transcribe] Loading {backend_name} model {model_repo}...")
            t0 = time.time()
            _backend = create_backend(backend_name, model_repo)
            _backend.load()
            _backend_name = backend_name
            _backend_model_repo = model_repo
            _ready.set()
            _log(f"[transcribe] Backend ready in {time.time() - t0:.1f}s")
        _last_used = time.time()
        _schedule_unload()


def _schedule_unload():
    global _unload_timer
    if _unload_timer:
        _unload_timer.cancel()
    _unload_timer = threading.Timer(IDLE_TIMEOUT, _try_unload)
    _unload_timer.daemon = True
    _unload_timer.start()


def _try_unload():
    global _backend, _backend_name, _backend_model_repo, _unload_timer
    with _model_lock:
        if time.time() - _last_used >= IDLE_TIMEOUT:
            _log("[transcribe] Unloading backend (idle timeout)")
            _backend = None
            _backend_name = None
            _backend_model_repo = None
            _ready.clear()
            _unload_timer = None


def preload():
    """Pre-load the model at startup so first transcription is instant."""
    _ensure_loaded()


def transcribe(audio: np.ndarray) -> str:
    """Transcribe a numpy audio array (16kHz float32 mono) to text."""
    if audio.size == 0:
        return ""
    _ensure_loaded()
    t0 = time.time()
    result = _backend.transcribe(audio)
    _log(f"[transcribe] Transcribed in {time.time() - t0:.1f}s")
    return result.strip()


def transcribe_segments(audio: np.ndarray) -> list[dict]:
    """Transcribe audio and return timestamped segments."""
    if audio.size == 0:
        return []
    _ensure_loaded()
    t0 = time.time()
    segments = _backend.transcribe_segments(audio)
    _log(f"[transcribe] Segmented transcription in {time.time() - t0:.1f}s")
    return segments
