import objc
from AppKit import (
    NSApp,
    NSBackingStoreBuffered,
    NSBezelStyleRounded,
    NSButton,
    NSButtonTypeSwitch,
    NSMakeRect,
    NSPopUpButton,
    NSTabView,
    NSTabViewItem,
    NSTextField,
    NSView,
    NSWindow,
    NSWindowStyleMaskClosable,
    NSWindowStyleMaskMiniaturizable,
    NSWindowStyleMaskTitled,
)
from Foundation import NSObject


def _label(text: str):
    return NSTextField.labelWithString_(text)


def _checkbox(title: str, target, selector: str):
    button = NSButton.alloc().initWithFrame_(NSMakeRect(0, 0, 320, 24))
    button.setButtonType_(NSButtonTypeSwitch)
    button.setTitle_(title)
    button.setTarget_(target)
    button.setAction_(selector)
    return button


def _action_button(title: str, target, selector: str):
    button = NSButton.alloc().initWithFrame_(NSMakeRect(0, 0, 160, 30))
    button.setTitle_(title)
    button.setTarget_(target)
    button.setAction_(selector)
    button.setBezelStyle_(NSBezelStyleRounded)
    return button


class PreferencesWindowController(NSObject):
    def initWithOwner_(self, owner):
        self = objc.super(PreferencesWindowController, self).init()
        if self is None:
            return None
        self.owner = owner
        self.window = None
        return self

    def build(self):
        style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
        self.window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(260, 220, 720, 460),
            style,
            NSBackingStoreBuffered,
            False,
        )
        self.window.setTitle_("Preferences")
        self.window.setDelegate_(self)

        content = self.window.contentView()
        tab_view = NSTabView.alloc().initWithFrame_(content.bounds())
        tab_view.setAutoresizingMask_(18)
        content.addSubview_(tab_view)

        tab_view.addTabViewItem_(self._general_tab())
        tab_view.addTabViewItem_(self._transcription_tab())
        tab_view.addTabViewItem_(self._privacy_tab())
        tab_view.addTabViewItem_(self._advanced_tab())

        self.refresh()

    def show(self):
        if self.window is None:
            self.build()
        self.refresh()
        self.window.makeKeyAndOrderFront_(None)
        NSApp.activateIgnoringOtherApps_(True)
        self.owner.update_window_activation()

    def _general_tab(self):
        view = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, 680, 400))
        self.launch_checkbox = _checkbox("Launch at login", self, "toggleLaunchAtLogin:")
        self.launch_checkbox.setFrameOrigin_((24, 320))
        view.addSubview_(self.launch_checkbox)

        self.dashboard_checkbox = _checkbox("Open dashboard on launch", self, "toggleOpenDashboardOnLaunch:")
        self.dashboard_checkbox.setFrameOrigin_((24, 280))
        view.addSubview_(self.dashboard_checkbox)

        self.indicator_checkbox = _checkbox("Show floating indicator", self, "toggleFloatingIndicator:")
        self.indicator_checkbox.setFrameOrigin_((24, 240))
        view.addSubview_(self.indicator_checkbox)

        item = NSTabViewItem.alloc().initWithIdentifier_("general")
        item.setLabel_("General")
        item.setView_(view)
        return item

    def _transcription_tab(self):
        view = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, 680, 400))
        label = _label("Backend")
        label.setFrame_(NSMakeRect(24, 320, 80, 24))
        view.addSubview_(label)

        self.backend_popup = NSPopUpButton.alloc().initWithFrame_pullsDown_(NSMakeRect(120, 316, 260, 28), False)
        self.backend_popup.setTarget_(self)
        self.backend_popup.setAction_("backendChanged:")
        view.addSubview_(self.backend_popup)

        self.model_label = _label("")
        self.model_label.setFrame_(NSMakeRect(24, 272, 620, 24))
        view.addSubview_(self.model_label)

        item = NSTabViewItem.alloc().initWithIdentifier_("transcription")
        item.setLabel_("Transcription")
        item.setView_(view)
        return item

    def _privacy_tab(self):
        view = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, 680, 400))
        self.db_path_label = _label("")
        self.db_path_label.setFrame_(NSMakeRect(24, 320, 620, 24))
        view.addSubview_(self.db_path_label)

        self.cache_path_label = _label("")
        self.cache_path_label.setFrame_(NSMakeRect(24, 288, 620, 24))
        view.addSubview_(self.cache_path_label)

        clear_dictations = _action_button("Clear dictations", self, "clearDictations:")
        clear_dictations.setFrameOrigin_((24, 220))
        view.addSubview_(clear_dictations)

        clear_meetings = _action_button("Clear meetings", self, "clearMeetings:")
        clear_meetings.setFrameOrigin_((200, 220))
        view.addSubview_(clear_meetings)

        clear_all = _action_button("Clear all history", self, "clearAllHistory:")
        clear_all.setFrameOrigin_((360, 220))
        view.addSubview_(clear_all)

        item = NSTabViewItem.alloc().initWithIdentifier_("privacy")
        item.setLabel_("Privacy & Storage")
        item.setView_(view)
        return item

    def _advanced_tab(self):
        view = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, 680, 400))
        reset_indicator = _action_button("Reset indicator position", self, "resetIndicatorPosition:")
        reset_indicator.setFrameOrigin_((24, 320))
        view.addSubview_(reset_indicator)

        reset_config = _action_button("Reset app config", self, "resetConfig:")
        reset_config.setFrameOrigin_((24, 280))
        view.addSubview_(reset_config)

        item = NSTabViewItem.alloc().initWithIdentifier_("advanced")
        item.setLabel_("Advanced")
        item.setView_(view)
        return item

    def refresh(self):
        cfg = self.owner.get_config()
        self.launch_checkbox.setState_(1 if cfg.get("launch_at_login") else 0)
        self.dashboard_checkbox.setState_(1 if cfg.get("open_dashboard_on_launch") else 0)
        self.indicator_checkbox.setState_(1 if cfg.get("show_floating_indicator", True) else 0)

        self.backend_popup.removeAllItems()
        selected_backend, selected_model = self.owner.get_selected_backend()
        selected_index = 0
        for idx, (backend_name, model_repo, label) in enumerate(self.owner.backend_options):
            self.backend_popup.addItemWithTitle_(label)
            if backend_name == selected_backend and (model_repo or "") == (selected_model or ""):
                selected_index = idx
        self.backend_popup.selectItemAtIndex_(selected_index)
        self.model_label.setStringValue_(f"Model: {self.owner.get_active_or_selected_model_label()}")
        self.db_path_label.setStringValue_(f"Database: {self.owner.database_path}")
        self.cache_path_label.setStringValue_(f"Model cache: {self.owner.model_cache_path}")

    def toggleLaunchAtLogin_(self, sender):
        self.owner.set_launch_at_login(bool(sender.state()))

    def toggleOpenDashboardOnLaunch_(self, sender):
        self.owner.update_config_value("open_dashboard_on_launch", bool(sender.state()))

    def toggleFloatingIndicator_(self, sender):
        self.owner.update_config_value("show_floating_indicator", bool(sender.state()))

    def backendChanged_(self, sender):
        backend_name, model_repo, _label_text = self.owner.backend_options[sender.indexOfSelectedItem()]
        self.owner.select_backend(backend_name, model_repo)
        self.refresh()

    def clearDictations_(self, _sender):
        self.owner.clear_dictation_history()
        self.refresh()

    def clearMeetings_(self, _sender):
        self.owner.clear_meeting_history()
        self.refresh()

    def clearAllHistory_(self, _sender):
        self.owner.clear_all_history()
        self.refresh()

    def resetIndicatorPosition_(self, _sender):
        self.owner.reset_indicator_position()

    def resetConfig_(self, _sender):
        self.owner.reset_config()
        self.refresh()

    def windowWillClose_(self, _notification):
        self.owner.update_window_activation()
