import json
import os

CONFIG_DIR = os.path.expanduser("~/Library/Application Support/Muesli")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.json")

DEFAULTS = {
    "hotkey": "cmd+shift+.",
    "stt_backend": "whisper",
    "stt_model": "",
    "whisper_model": "mlx-community/whisper-small.en-mlx",
    "idle_timeout": 120,
    "auto_record_meetings": False,
    "launch_at_login": False,
    "open_dashboard_on_launch": True,
    "show_floating_indicator": True,
    "dashboard_window_frame": None,
}


def load() -> dict:
    os.makedirs(CONFIG_DIR, exist_ok=True)
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH) as f:
            saved = json.load(f)
        return {**DEFAULTS, **saved}
    return dict(DEFAULTS)


def save(cfg: dict):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(CONFIG_PATH, "w") as f:
        json.dump(cfg, f, indent=2)
