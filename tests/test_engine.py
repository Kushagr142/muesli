import numpy as np
from unittest.mock import patch, MagicMock
import config
import transcribe.engine as engine


class TestTranscribeEngine:
    def setup_method(self):
        engine._backend = None
        engine._backend_name = None
        engine._backend_model_repo = None

    def test_empty_audio_returns_empty(self):
        result = engine.transcribe(np.array([], dtype=np.float32))
        assert result == ""

    @patch("transcribe.engine._ensure_loaded")
    def test_transcribe_calls_backend(self, mock_load):
        engine._backend = MagicMock()
        engine._backend.transcribe.return_value = " Hello world "
        result = engine.transcribe(np.zeros(16000, dtype=np.float32))
        assert result == "Hello world"
        engine._backend.transcribe.assert_called_once()

    @patch("transcribe.engine._ensure_loaded")
    def test_transcribe_strips_whitespace(self, mock_load):
        engine._backend = MagicMock()
        engine._backend.transcribe.return_value = "  spaced out  "
        result = engine.transcribe(np.ones(16000, dtype=np.float32))
        assert result == "spaced out"

    @patch("transcribe.engine._ensure_loaded")
    def test_transcribe_handles_empty_result(self, mock_load):
        engine._backend = MagicMock()
        engine._backend.transcribe.return_value = ""
        result = engine.transcribe(np.ones(16000, dtype=np.float32))
        assert result == ""

    @patch("transcribe.engine.config.load")
    def test_resolve_backend_settings_uses_whisper_defaults(self, mock_load):
        mock_load.return_value = dict(config.DEFAULTS)
        backend_name, model_repo = engine._resolve_backend_settings()
        assert backend_name == "whisper"
        assert model_repo == config.DEFAULTS["whisper_model"]

    @patch("transcribe.engine.config.load")
    def test_resolve_backend_settings_uses_qwen_default(self, mock_load):
        cfg = dict(config.DEFAULTS)
        cfg["stt_backend"] = "qwen"
        cfg["stt_model"] = ""
        mock_load.return_value = cfg
        backend_name, model_repo = engine._resolve_backend_settings()
        assert backend_name == "qwen"
        assert model_repo == "mlx-community/Qwen3-ASR-0.6B-4bit"
