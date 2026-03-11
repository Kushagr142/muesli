import os
import threading
from datetime import datetime

from AppKit import (
    NSApplication,
    NSApplicationActivationPolicyAccessory,
    NSApplicationActivationPolicyRegular,
    NSImage,
    NSPasteboard,
    NSPasteboardTypeString,
)
from PyObjCTools import AppHelper

import config
from audio.mic_capture import MicCapture
from cal_monitor.monitor import CalendarMonitor
from dictation.hotkey import HoldToRecord
from dictation.paste import paste_text
from meeting.session import MeetingSession
from storage.local_db import (
    DB_PATH,
    delete_all_history,
    delete_dictation_history,
    delete_meeting_history,
    get_recent_activity,
    get_recent_dictations,
    get_recent_meetings,
    init_db,
    save_dictation,
)
from storage.stats import get_dictation_stats, get_home_stats, get_meeting_stats
from transcribe import engine
from ui.app_delegate import MuesliAppDelegate
from ui.dashboard_window import DashboardWindowController
from ui.floating_indicator import FloatingIndicator
from ui.preferences_window import PreferencesWindowController
from ui.status_item import StatusItemController

MENU_TITLE_IDLE = ""
MENU_TITLE_RECORDING = ""
MENU_TITLE_TRANSCRIBING = ""
MENU_TITLE_MEETING = ""

BACKEND_OPTIONS = [
    ("whisper", "", "Whisper Small"),
    ("qwen", "mlx-community/Qwen3-ASR-0.6B-4bit", "Qwen3 ASR 0.6B 4-bit"),
]

MAX_DICTATION_LABEL = 56
MENU_ICON_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "menu_m_template.png")
APP_ICON_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "muesli_app_icon.png")
MODEL_CACHE_PATH = os.path.expanduser("~/.cache/huggingface/hub")


class MuesliApp:
    backend_options = BACKEND_OPTIONS
    database_path = DB_PATH
    model_cache_path = MODEL_CACHE_PATH

    def __init__(self):
        self._cfg = config.load()
        self._transcribing = False
        self._meeting: MeetingSession | None = None
        self._dictation_started_at: datetime | None = None
        self._indicator = FloatingIndicator() if self._cfg.get("show_floating_indicator", True) else None

        self.mic = MicCapture()
        self.hotkey = HoldToRecord(
            on_prepare=self._on_dictation_prepare,
            on_start=self._on_dictation_start,
            on_stop=self._on_dictation_stop,
            on_cancel=self._on_dictation_cancel,
        )
        self._calendar = CalendarMonitor(on_meeting_soon=self._on_meeting_soon)

        self._delegate = None
        self._status_item = None
        self._dashboard = None
        self._preferences = None

        init_db()

    def run(self):
        app = NSApplication.sharedApplication()
        app.setActivationPolicy_(NSApplicationActivationPolicyAccessory)

        self._delegate = MuesliAppDelegate.alloc().initWithOwner_(self)
        app.setDelegate_(self._delegate)

        try:
            self.hotkey.start()
        except Exception as exc:
            print(f"[muesli] Hotkey listener failed to start: {exc}")
        self._calendar.start()
        threading.Thread(target=engine.preload, daemon=True).start()

        print("[muesli] Hotkey listener started (Hold Left Cmd)")
        print("[muesli] Calendar monitor started")
        print("[muesli] Hold to dictate, or use menu to start meeting recording")
        AppHelper.runEventLoop()

    def on_app_launched(self):
        self._set_application_icon()
        self._status_item = StatusItemController.alloc().initWithOwner_iconPath_(
            self,
            MENU_ICON_PATH if os.path.exists(MENU_ICON_PATH) else None,
        )
        self._status_item.build()
        self._ensure_runtime_ready()
        self.set_status("Idle")
        if self._cfg.get("open_dashboard_on_launch", True):
            self.show_dashboard()
        else:
            self._update_activation_policy()

    def shutdown(self):
        if self._meeting and self._meeting.is_recording:
            self._meeting.stop()
        self.hotkey.stop()
        self._calendar.stop()
        if self._indicator is not None:
            self._indicator.close()

    def quit(self):
        NSApplication.sharedApplication().terminate_(None)

    def set_status(self, text: str, menu_title: str = MENU_TITLE_IDLE, overlay_state: str = "idle"):
        def _apply():
            if self._status_item is not None:
                self._status_item.set_title(menu_title)
                self._status_item.set_status_text(text)
            if self._indicator is not None:
                self._indicator.set_state(overlay_state)

        AppHelper.callAfter(_apply)

    def truncate_text(self, text: str, limit: int = MAX_DICTATION_LABEL) -> str:
        compact = " ".join((text or "").split())
        if len(compact) <= limit:
            return compact
        return compact[: limit - 3].rstrip() + "..."

    def get_config(self) -> dict:
        self._cfg = config.load()
        return dict(self._cfg)

    def update_config_value(self, key: str, value):
        cfg = self.get_config()
        cfg[key] = value
        config.save(cfg)
        self._cfg = cfg
        if key == "show_floating_indicator":
            self._apply_indicator_visibility()
        self.refresh_ui()

    def reset_config(self):
        config.save(dict(config.DEFAULTS))
        self._cfg = config.load()
        self._apply_indicator_visibility()
        self.refresh_ui()

    def _apply_indicator_visibility(self):
        show_indicator = self._cfg.get("show_floating_indicator", True)
        if show_indicator and self._indicator is None:
            self._indicator = FloatingIndicator()
        elif not show_indicator and self._indicator is not None:
            self._indicator.close()
            self._indicator = None

    def _ensure_runtime_ready(self):
        if not self.hotkey.is_running:
            print("[muesli] Hotkey listener was not running; restarting it")
            try:
                self.hotkey.restart()
            except Exception as exc:
                print(f"[muesli] Hotkey restart failed: {exc}")
        if self._cfg.get("show_floating_indicator", True):
            if self._indicator is None:
                self._indicator = FloatingIndicator()
            else:
                self._indicator.ensure_visible()

    def reset_indicator_position(self):
        cfg = self.get_config()
        cfg.pop("indicator_origin", None)
        config.save(cfg)
        self._cfg = cfg
        if self._indicator is not None:
            self._indicator.close()
            self._indicator = FloatingIndicator()

    def get_selected_backend(self) -> tuple[str, str]:
        cfg = self.get_config()
        return cfg.get("stt_backend") or "whisper", cfg.get("stt_model") or ""

    def get_active_or_selected_model_label(self) -> str:
        backend_name, model_repo = self.get_selected_backend()
        if backend_name == "whisper":
            return model_repo or self._cfg.get("whisper_model")
        return model_repo or "mlx-community/Qwen3-ASR-0.6B-4bit"

    def select_backend(self, backend_name: str, model_repo: str):
        cfg = self.get_config()
        cfg["stt_backend"] = backend_name
        cfg["stt_model"] = model_repo
        config.save(cfg)
        self._cfg = cfg
        threading.Thread(target=engine.preload, daemon=True).start()
        self.set_status(f"Backend: {backend_name.title()}")
        self.refresh_ui()

    def get_recent_dictations(self, limit: int = 10) -> list[dict]:
        return get_recent_dictations(limit=limit)

    def get_recent_meetings(self, limit: int = 10) -> list[dict]:
        return get_recent_meetings(limit=limit)

    def get_recent_meeting_transcripts(self, limit: int = 10) -> list[dict]:
        return get_recent_meetings(limit=limit)

    def get_dashboard_frame(self):
        return self.get_config().get("dashboard_window_frame")

    def save_dashboard_frame(self, frame: dict):
        cfg = self.get_config()
        cfg["dashboard_window_frame"] = frame
        config.save(cfg)
        self._cfg = cfg

    def get_dashboard_snapshot(self, filter_kind: str = "all") -> dict:
        return {
            "dictation": get_dictation_stats(),
            "meetings": get_meeting_stats(),
            "home": get_home_stats(),
            "activity": get_recent_activity(limit=100, filter_kind=filter_kind),
        }

    def show_dashboard(self):
        self._ensure_runtime_ready()
        if self._dashboard is None:
            self._dashboard = DashboardWindowController.alloc().initWithOwner_(self)
        self._dashboard.show()

    def show_preferences(self):
        if self._preferences is None:
            self._preferences = PreferencesWindowController.alloc().initWithOwner_(self)
        self._preferences.show()

    def update_window_activation(self):
        self._update_activation_policy()

    def refresh_ui(self):
        def _refresh():
            if self._status_item is not None:
                self._status_item.refresh()
            if self._dashboard is not None:
                self._dashboard.refresh_content()
            if self._preferences is not None:
                self._preferences.refresh()

        AppHelper.callAfter(_refresh)

    def _has_visible_windows(self) -> bool:
        controllers = [self._dashboard, self._preferences]
        for controller in controllers:
            window = getattr(controller, "window", None)
            if window is not None and window.isVisible():
                return True
        return False

    def _update_activation_policy(self):
        app = NSApplication.sharedApplication()
        should_show_dock = self._has_visible_windows()
        target_policy = (
            NSApplicationActivationPolicyRegular if should_show_dock else NSApplicationActivationPolicyAccessory
        )
        app.setActivationPolicy_(target_policy)
        self._set_application_icon()
        if should_show_dock:
            app.activateIgnoringOtherApps_(True)

    def _set_application_icon(self):
        if not os.path.exists(APP_ICON_PATH):
            return
        image = NSImage.alloc().initByReferencingFile_(APP_ICON_PATH)
        if image is not None:
            NSApplication.sharedApplication().setApplicationIconImage_(image)

    def copy_activity_text(self, row: dict):
        text = row.get("full_text") or row.get("preview_text") or row.get("title") or ""
        pasteboard = NSPasteboard.generalPasteboard()
        pasteboard.clearContents()
        pasteboard.setString_forType_(text, NSPasteboardTypeString)

    def clear_dictation_history(self):
        delete_dictation_history()
        self.refresh_ui()

    def clear_meeting_history(self):
        delete_meeting_history()
        self.refresh_ui()

    def clear_all_history(self):
        delete_all_history()
        self.refresh_ui()

    def is_meeting_recording(self) -> bool:
        return bool(self._meeting and self._meeting.is_recording)

    def toggle_meeting(self):
        if self._meeting and self._meeting.is_recording:
            self._stop_meeting()
        else:
            self._start_meeting()

    def _start_meeting(self, title: str = "Meeting"):
        self._meeting = MeetingSession(title=title)
        self._meeting.start()
        self.set_status(f"Meeting: {title}", MENU_TITLE_MEETING, "meeting")
        self.refresh_ui()

    def _stop_meeting(self):
        if not self._meeting:
            return
        self.set_status("Processing meeting...", MENU_TITLE_TRANSCRIBING, "processing")

        def process():
            try:
                result = self._meeting.stop()
                print(f"[muesli] Meeting saved: #{result['id']}")
            except Exception as exc:
                print(f"[muesli] Meeting processing error: {exc}")
            finally:
                self._meeting = None
                self.set_status("Idle")
                self.refresh_ui()

        threading.Thread(target=process, daemon=True).start()

    def _on_meeting_soon(self, event_info):
        print(f"[muesli] Meeting soon: {event_info['title']}")

    def _on_dictation_prepare(self):
        if self.is_meeting_recording():
            return
        self.mic.prepare()

    def _on_dictation_start(self):
        if self.is_meeting_recording():
            return
        self._dictation_started_at = datetime.now()
        self.mic.start()
        self.set_status("Recording...", MENU_TITLE_RECORDING, "listening")
        print("[muesli] Dictation started")

    def _on_dictation_stop(self):
        if self.is_meeting_recording():
            return
        audio = self.mic.stop()
        duration = len(audio) / MicCapture.SAMPLE_RATE if len(audio) > 0 else 0
        ended_at = datetime.now()
        started_at = self._dictation_started_at or ended_at
        self._dictation_started_at = None
        print(f"[muesli] Dictation stopped ({duration:.1f}s)")

        if duration < 0.3:
            self.set_status("Idle")
            return

        self.set_status("Transcribing...", MENU_TITLE_TRANSCRIBING, "transcribing")
        self._transcribing = True

        def do_transcribe():
            try:
                text = engine.transcribe(audio)
                print(f"[muesli] Transcribed: {text}")
                if text:
                    save_dictation(
                        text,
                        duration,
                        started_at=started_at,
                        ended_at=ended_at,
                    )
                    paste_text(text)
            except Exception as exc:
                print(f"[muesli] Transcription error: {exc}")
            finally:
                self._transcribing = False
                self.set_status("Idle")
                self.refresh_ui()

        threading.Thread(target=do_transcribe, daemon=True).start()

    def _on_dictation_cancel(self):
        if self.is_meeting_recording():
            return
        self._dictation_started_at = None
        self.mic.cancel()

    def set_launch_at_login(self, enabled: bool):
        cfg = self.get_config()
        cfg["launch_at_login"] = enabled
        config.save(cfg)
        self._cfg = cfg

        bundle_path = NSBundle.mainBundle().bundlePath()
        if not bundle_path.endswith(".app"):
            print("[muesli] Launch at login requires running from a bundled .app")
            self.refresh_ui()
            return

        app_name = os.path.splitext(os.path.basename(bundle_path))[0]
        if enabled:
            script = (
                'tell application "System Events" to make login item at end '
                f'with properties {{name:"{app_name}", path:"{bundle_path}", hidden:false}}'
            )
        else:
            script = (
                'tell application "System Events" to delete login item '
                f'"{app_name}"'
            )

        try:
            subprocess.run(["osascript", "-e", script], check=False, capture_output=True, text=True)
        except Exception as exc:
            print(f"[muesli] Launch-at-login update failed: {exc}")
        self.refresh_ui()
