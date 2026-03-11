import objc
from AppKit import (
    NSImage,
    NSMenu,
    NSMenuItem,
    NSPasteboard,
    NSPasteboardTypeString,
    NSStatusBar,
)
from Foundation import NSObject


class StatusItemController(NSObject):
    def initWithOwner_iconPath_(self, owner, icon_path):
        self = objc.super(StatusItemController, self).init()
        if self is None:
            return None
        self.owner = owner
        self.icon_path = icon_path
        self.status_item = None
        self.recent_items_menu = None
        self.recent_meetings_menu = None
        self.backend_menu = None
        self.meeting_item = None
        self.status_item_label = None
        self._recent_text_by_tag = {}
        self._recent_meeting_text_by_tag = {}
        self._backend_by_tag = {}
        return self

    def build(self):
        target = self.owner._delegate
        self.status_item = NSStatusBar.systemStatusBar().statusItemWithLength_(-1)
        button = self.status_item.button()
        if button is not None:
            button.setTitle_("Mu")
            if self.icon_path:
                image = NSImage.alloc().initByReferencingFile_(self.icon_path)
                if image is not None:
                    image.setTemplate_(False)
                    button.setImage_(image)
            button.setToolTip_("Muesli")

        menu = NSMenu.alloc().init()
        menu.addItem_(self._action_item("Open Muesli", "openDashboard:", target))
        menu.addItem_(NSMenuItem.separatorItem())

        recent_parent = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_("Recent Dictations", None, "")
        self.recent_items_menu = NSMenu.alloc().init()
        recent_parent.setSubmenu_(self.recent_items_menu)
        menu.addItem_(recent_parent)

        meetings_parent = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_("Meeting Transcripts", None, "")
        self.recent_meetings_menu = NSMenu.alloc().init()
        meetings_parent.setSubmenu_(self.recent_meetings_menu)
        menu.addItem_(meetings_parent)

        backend_parent = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_("Transcription Backend", None, "")
        self.backend_menu = NSMenu.alloc().init()
        backend_parent.setSubmenu_(self.backend_menu)
        menu.addItem_(backend_parent)

        menu.addItem_(NSMenuItem.separatorItem())
        self.meeting_item = self._action_item("Start Meeting Recording", "toggleMeeting:", target)
        menu.addItem_(self.meeting_item)
        menu.addItem_(NSMenuItem.separatorItem())
        menu.addItem_(self._action_item("Settings…", "openPreferences:", target))

        self.status_item_label = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_("Status: Idle", None, "")
        menu.addItem_(self.status_item_label)
        menu.addItem_(NSMenuItem.separatorItem())
        menu.addItem_(self._action_item("Quit", "quitApp:", target))

        self.status_item.setMenu_(menu)
        self.refresh()

    def _action_item(self, title, selector, target):
        item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(title, selector, "")
        item.setTarget_(target)
        return item

    def set_title(self, title: str):
        if self.status_item is None:
            return
        button = self.status_item.button()
        if button is not None:
            button.setTitle_(title)

    def set_status_text(self, text: str):
        if self.status_item_label is not None:
            self.status_item_label.setTitle_(f"Status: {text}")

    def refresh(self):
        self.refresh_recent_dictations()
        self.refresh_recent_meetings()
        self.refresh_backend_menu()
        self.refresh_meeting_title()

    def refresh_recent_dictations(self):
        if self.recent_items_menu is None:
            return
        self.recent_items_menu.removeAllItems()
        self._recent_text_by_tag = {}
        dictations = self.owner.get_recent_dictations(limit=10)
        if not dictations:
            item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_("No dictations yet", None, "")
            item.setEnabled_(False)
            self.recent_items_menu.addItem_(item)
            return

        for idx, entry in enumerate(dictations):
            label = self.owner.truncate_text(entry.get("raw_text", ""), limit=54) or "(empty)"
            item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(label, "copyRecentDictation:", "")
            item.setTarget_(self.owner._delegate)
            item.setTag_(idx)
            self._recent_text_by_tag[idx] = entry.get("raw_text", "")
            self.recent_items_menu.addItem_(item)

    def refresh_recent_meetings(self):
        if self.recent_meetings_menu is None:
            return
        self.recent_meetings_menu.removeAllItems()
        self._recent_meeting_text_by_tag = {}
        meetings = self.owner.get_recent_meeting_transcripts(limit=10)
        if not meetings:
            item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_("No meetings yet", None, "")
            item.setEnabled_(False)
            self.recent_meetings_menu.addItem_(item)
            return

        for idx, entry in enumerate(meetings):
            title = entry.get("title") or "Meeting"
            transcript = self.owner.truncate_text(entry.get("raw_transcript", ""), limit=42) or "(empty)"
            label = self.owner.truncate_text(f"{title}: {transcript}", limit=54)
            item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(label, "copyRecentMeeting:", "")
            item.setTarget_(self.owner._delegate)
            item.setTag_(idx)
            self._recent_meeting_text_by_tag[idx] = entry.get("raw_transcript", "")
            self.recent_meetings_menu.addItem_(item)

    def refresh_backend_menu(self):
        if self.backend_menu is None:
            return
        self.backend_menu.removeAllItems()
        self._backend_by_tag = {}
        selected_backend, selected_model = self.owner.get_selected_backend()
        for idx, (backend_name, model_repo, label) in enumerate(self.owner.backend_options):
            prefix = "✓ " if backend_name == selected_backend and (model_repo or "") == (selected_model or "") else ""
            item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(f"{prefix}{label}", "selectBackend:", "")
            item.setTarget_(self.owner._delegate)
            item.setTag_(idx)
            self._backend_by_tag[idx] = (backend_name, model_repo)
            self.backend_menu.addItem_(item)

    def refresh_meeting_title(self):
        if self.meeting_item is None:
            return
        if self.owner.is_meeting_recording():
            self.meeting_item.setTitle_("Stop Meeting Recording")
        else:
            self.meeting_item.setTitle_("Start Meeting Recording")

    def copy_recent_dictation(self, tag: int):
        text = self._recent_text_by_tag.get(tag, "")
        pasteboard = NSPasteboard.generalPasteboard()
        pasteboard.clearContents()
        pasteboard.setString_forType_(text, NSPasteboardTypeString)

    def copy_recent_meeting(self, tag: int):
        text = self._recent_meeting_text_by_tag.get(tag, "")
        pasteboard = NSPasteboard.generalPasteboard()
        pasteboard.clearContents()
        pasteboard.setString_forType_(text, NSPasteboardTypeString)

    def select_backend_for_tag(self, tag: int):
        backend_name, model_repo = self._backend_by_tag.get(tag, ("whisper", ""))
        self.owner.select_backend(backend_name, model_repo)
