import json
import tempfile
import wave

import numpy as np

from bridge.worker import SpeechWorker, WorkerError, _handle_message


def _write_test_wav(path, samples, sample_rate=16000):
    with wave.open(path, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes((samples * 32767).astype(np.int16).tobytes())


class DummyBackend:
    def __init__(self):
        self.audio_lengths = []

    def load(self):
        return None

    def transcribe(self, audio):
        self.audio_lengths.append(len(audio))
        return "hello from worker"


class TestSpeechWorker:
    def test_ping(self):
        worker = SpeechWorker()
        response, should_exit = _handle_message(
            worker,
            {"id": "1", "method": "ping", "params": {}},
        )
        assert response["ok"] is True
        assert response["result"]["status"] == "ok"
        assert should_exit is False

    def test_shutdown(self):
        worker = SpeechWorker()
        response, should_exit = _handle_message(
            worker,
            {"id": "1", "method": "shutdown", "params": {}},
        )
        assert response["ok"] is True
        assert should_exit is True

    def test_unknown_method_raises_worker_error(self):
        worker = SpeechWorker()
        try:
            _handle_message(worker, {"id": "1", "method": "nope", "params": {}})
        except WorkerError as exc:
            assert exc.code == "UNKNOWN_METHOD"
        else:  # pragma: no cover
            raise AssertionError("Expected WorkerError")

    def test_transcribe_file_uses_loaded_backend(self):
        worker = SpeechWorker()
        backend = DummyBackend()
        worker._backend = backend
        worker._backend_name = "whisper"
        worker._backend_model = "mlx-community/whisper-small.en-mlx"

        with tempfile.NamedTemporaryFile(suffix=".wav") as wav_file:
            _write_test_wav(wav_file.name, np.ones(1600, dtype=np.float32))
            result = worker.transcribe_file(
                {
                    "wav_path": wav_file.name,
                    "backend": "whisper",
                    "model": "mlx-community/whisper-small.en-mlx",
                }
            )

        assert result["text"] == "hello from worker"
        assert backend.audio_lengths == [1600]

    def test_transcribe_file_validates_path(self):
        worker = SpeechWorker()
        try:
            worker.transcribe_file({"wav_path": "/tmp/does-not-exist.wav"})
        except WorkerError as exc:
            assert exc.code == "FILE_NOT_FOUND"
        else:  # pragma: no cover
            raise AssertionError("Expected WorkerError")

    def test_transcribe_file_validates_sample_rate(self):
        worker = SpeechWorker()
        backend = DummyBackend()
        worker._backend = backend
        worker._backend_name = "whisper"
        worker._backend_model = "mlx-community/whisper-small.en-mlx"

        with tempfile.NamedTemporaryFile(suffix=".wav") as wav_file:
            _write_test_wav(wav_file.name, np.ones(1600, dtype=np.float32), sample_rate=44100)
            try:
                worker.transcribe_file(
                    {
                        "wav_path": wav_file.name,
                        "backend": "whisper",
                        "model": "mlx-community/whisper-small.en-mlx",
                    }
                )
            except WorkerError as exc:
                assert exc.code == "UNSUPPORTED_SAMPLE_RATE"
            else:  # pragma: no cover
                raise AssertionError("Expected WorkerError")
