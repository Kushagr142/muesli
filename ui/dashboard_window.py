import objc
from AppKit import (
    NSApp,
    NSBackingStoreBuffered,
    NSBezelStyleRounded,
    NSButton,
    NSFont,
    NSMakeRect,
    NSTabView,
    NSTabViewItem,
    NSScrollView,
    NSStackView,
    NSTableColumn,
    NSTableView,
    NSTextField,
    NSWindow,
    NSWindowStyleMaskClosable,
    NSWindowStyleMaskMiniaturizable,
    NSWindowStyleMaskResizable,
    NSWindowStyleMaskTitled,
)
from Foundation import NSObject


def _label(text: str, font_size: float = 13, bold: bool = False):
    field = NSTextField.labelWithString_(text)
    field.setFont_(NSFont.boldSystemFontOfSize_(font_size) if bold else NSFont.systemFontOfSize_(font_size))
    return field


def _button(title: str, target, selector: str):
    button = NSButton.alloc().initWithFrame_(NSMakeRect(0, 0, 160, 32))
    button.setTitle_(title)
    button.setTarget_(target)
    button.setAction_(selector)
    button.setBezelStyle_(NSBezelStyleRounded)
    return button


def _build_table(columns: list[tuple[str, str, float]], target, action: str):
    scroll_view = NSScrollView.alloc().initWithFrame_(NSMakeRect(0, 0, 900, 220))
    scroll_view.setHasVerticalScroller_(True)
    scroll_view.setAutoresizingMask_(18)

    table_view = NSTableView.alloc().initWithFrame_(scroll_view.bounds())
    table_view.setDelegate_(target)
    table_view.setDataSource_(target)
    table_view.setUsesAlternatingRowBackgroundColors_(True)
    table_view.setRowHeight_(34)
    table_view.setDoubleAction_(action)
    table_view.setTarget_(target)

    for identifier, title, width in columns:
        column = NSTableColumn.alloc().initWithIdentifier_(identifier)
        column.headerCell().setStringValue_(title)
        column.setWidth_(width)
        table_view.addTableColumn_(column)

    scroll_view.setDocumentView_(table_view)
    return scroll_view, table_view


class DashboardWindowController(NSObject):
    def initWithOwner_(self, owner):
        self = objc.super(DashboardWindowController, self).init()
        if self is None:
            return None
        self.owner = owner
        self.window = None
        self.dictation_rows = []
        self.meeting_rows = []
        self.dictation_table_view = None
        self.meeting_table_view = None
        self.transcript_tab_view = None
        return self

    def build(self):
        frame = self.owner.get_dashboard_frame() or {"x": 180, "y": 140, "width": 1040, "height": 760}
        rect = NSMakeRect(frame["x"], frame["y"], frame["width"], frame["height"])
        style = (
            NSWindowStyleMaskTitled
            | NSWindowStyleMaskClosable
            | NSWindowStyleMaskResizable
            | NSWindowStyleMaskMiniaturizable
        )
        self.window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            rect, style, NSBackingStoreBuffered, False
        )
        self.window.setTitle_("Muesli")
        self.window.setDelegate_(self)

        content = self.window.contentView()
        root = NSStackView.alloc().initWithFrame_(content.bounds())
        root.setOrientation_(1)
        root.setSpacing_(16)
        root.setEdgeInsets_((20, 24, 20, 24))
        root.setAutoresizingMask_(18)
        content.addSubview_(root)

        header = NSStackView.alloc().init()
        header.setOrientation_(1)
        header.setSpacing_(4)
        self.welcome_label = _label("Welcome back", 28, True)
        self.summary_chips = _label("Streak 0 days    0 words    0 WPM", 14, False)
        header.addArrangedSubview_(self.welcome_label)
        header.addArrangedSubview_(self.summary_chips)
        root.addArrangedSubview_(header)

        action_row = NSStackView.alloc().init()
        action_row.setOrientation_(0)
        action_row.setSpacing_(12)
        self.meeting_button = _button("Start Meeting Recording", self, "toggleMeeting:")
        action_row.addArrangedSubview_(self.meeting_button)
        action_row.addArrangedSubview_(_button("Open Settings", self, "openPreferences:"))
        action_row.addArrangedSubview_(_button("Refresh", self, "refreshPressed:"))
        root.addArrangedSubview_(action_row)

        self.dictation_stats = _label("", 14, False)
        self.meeting_stats = _label("", 14, False)
        root.addArrangedSubview_(self.dictation_stats)
        root.addArrangedSubview_(self.meeting_stats)

        self.transcript_tab_view = NSTabView.alloc().initWithFrame_(NSMakeRect(0, 0, frame["width"] - 48, 500))
        self.transcript_tab_view.setAutoresizingMask_(18)
        self.transcript_tab_view.addTabViewItem_(self._dictations_tab())
        self.transcript_tab_view.addTabViewItem_(self._meetings_tab())
        root.addArrangedSubview_(self.transcript_tab_view)

        self.refresh_content()

    def _dictations_tab(self):
        dictation_columns = [
            ("timestamp", "Time", 140),
            ("preview", "Transcript", 640),
            ("words", "Words", 80),
            ("duration", "Duration", 100),
        ]
        dictation_scroll, self.dictation_table_view = _build_table(
            dictation_columns, self, "copySelectedDictation:"
        )
        item = NSTabViewItem.alloc().initWithIdentifier_("dictations")
        item.setLabel_("Dictations")
        item.setView_(dictation_scroll)
        return item

    def _meetings_tab(self):
        meeting_columns = [
            ("timestamp", "Start", 140),
            ("title", "Meeting", 180),
            ("preview", "Transcript", 460),
            ("words", "Words", 80),
            ("duration", "Duration", 100),
        ]
        meeting_scroll, self.meeting_table_view = _build_table(
            meeting_columns, self, "copySelectedMeeting:"
        )
        item = NSTabViewItem.alloc().initWithIdentifier_("meetings")
        item.setLabel_("Meeting Transcripts")
        item.setView_(meeting_scroll)
        return item

    def show(self):
        if self.window is None:
            self.build()
        self.refresh_content()
        self.window.makeKeyAndOrderFront_(None)
        NSApp.activateIgnoringOtherApps_(True)
        self.owner.update_window_activation()

    def refresh_content(self):
        dictation = self.owner.get_dashboard_snapshot()["dictation"]
        meetings = self.owner.get_dashboard_snapshot()["meetings"]
        self.summary_chips.setStringValue_(
            f"Streak {dictation['current_streak_days']} days    {dictation['total_words']} dictation words    {dictation['average_wpm']:.1f} WPM"
        )
        self.dictation_stats.setStringValue_(
            "Dictation: "
            f"{dictation['total_sessions']} sessions, "
            f"{dictation['total_words']} words, "
            f"{dictation['average_words_per_session']:.1f} words/session, "
            f"longest streak {dictation['longest_streak_days']} days"
        )
        self.meeting_stats.setStringValue_(
            "Meetings: "
            f"{meetings['total_meetings']} meetings, "
            f"{meetings['total_words']} words, "
            f"{meetings['average_wpm']:.1f} WPM"
        )
        if self.owner.is_meeting_recording():
            self.meeting_button.setTitle_("Stop Meeting Recording")
        else:
            self.meeting_button.setTitle_("Start Meeting Recording")

        self.dictation_rows = self.owner.get_recent_dictations(limit=10)
        self.meeting_rows = self.owner.get_recent_meeting_transcripts(limit=10)

        if self.dictation_table_view is not None:
            self.dictation_table_view.reloadData()
        if self.meeting_table_view is not None:
            self.meeting_table_view.reloadData()

    def numberOfRowsInTableView_(self, table_view):
        if table_view == self.dictation_table_view:
            return len(self.dictation_rows)
        if table_view == self.meeting_table_view:
            return len(self.meeting_rows)
        return 0

    def tableView_objectValueForTableColumn_row_(self, table_view, table_column, row):
        if table_view == self.dictation_table_view:
            item = self.dictation_rows[row]
            return self._dictation_value(item, str(table_column.identifier()))
        if table_view == self.meeting_table_view:
            item = self.meeting_rows[row]
            return self._meeting_value(item, str(table_column.identifier()))
        return ""

    def _dictation_value(self, item: dict, identifier: str):
        if identifier == "timestamp":
            raw = item.get("timestamp", "")
            return raw.replace("T", " ")[:16] if "T" in raw else raw[:16]
        if identifier == "preview":
            return self.owner.truncate_text(item.get("raw_text", "") or "(empty)", 96)
        if identifier == "words":
            return str(item.get("word_count", 0))
        if identifier == "duration":
            duration = float(item.get("duration_seconds") or 0.0)
            return f"{duration:.0f}s"
        return ""

    def _meeting_value(self, item: dict, identifier: str):
        if identifier == "timestamp":
            raw = item.get("start_time", "")
            return raw.replace("T", " ")[:16] if "T" in raw else raw[:16]
        if identifier == "title":
            return self.owner.truncate_text(item.get("title", "") or "Meeting", 24)
        if identifier == "preview":
            return self.owner.truncate_text(item.get("raw_transcript", "") or "(empty)", 72)
        if identifier == "words":
            return str(item.get("word_count", 0))
        if identifier == "duration":
            duration = float(item.get("duration_seconds") or 0.0)
            return f"{duration:.0f}s"
        return ""

    def refreshPressed_(self, _sender):
        self.refresh_content()

    def toggleMeeting_(self, _sender):
        self.owner.toggle_meeting()
        self.refresh_content()

    def openPreferences_(self, _sender):
        self.owner.show_preferences()

    def copySelectedDictation_(self, _sender):
        selected_row = self.dictation_table_view.selectedRow()
        if selected_row < 0 or selected_row >= len(self.dictation_rows):
            return
        row = self.dictation_rows[selected_row]
        self.owner.copy_activity_text(
            {
                "preview_text": row.get("raw_text", ""),
                "full_text": row.get("raw_text", ""),
                "title": "",
            }
        )

    def copySelectedMeeting_(self, _sender):
        selected_row = self.meeting_table_view.selectedRow()
        if selected_row < 0 or selected_row >= len(self.meeting_rows):
            return
        row = self.meeting_rows[selected_row]
        self.owner.copy_activity_text(
            {
                "preview_text": row.get("raw_transcript", ""),
                "full_text": row.get("raw_transcript", ""),
                "title": row.get("title", ""),
            }
        )

    def tableViewSelectionDidChange_(self, notification):
        table_view = notification.object()
        if table_view == self.dictation_table_view:
            self.copySelectedDictation_(None)
        elif table_view == self.meeting_table_view:
            self.copySelectedMeeting_(None)

    def windowDidResize_(self, _notification):
        self._persist_frame()

    def windowDidMove_(self, _notification):
        self._persist_frame()

    def windowWillClose_(self, _notification):
        self.owner.update_window_activation()

    def _persist_frame(self):
        if self.window is None:
            return
        frame = self.window.frame()
        self.owner.save_dashboard_frame(
            {
                "x": frame.origin.x,
                "y": frame.origin.y,
                "width": frame.size.width,
                "height": frame.size.height,
            }
        )
