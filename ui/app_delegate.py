import objc
from Foundation import NSObject


class MuesliAppDelegate(NSObject):
    def initWithOwner_(self, owner):
        self = objc.super(MuesliAppDelegate, self).init()
        if self is None:
            return None
        self.owner = owner
        return self

    def applicationDidFinishLaunching_(self, _notification):
        self.owner.on_app_launched()

    def applicationWillTerminate_(self, _notification):
        self.owner.shutdown()

    def applicationShouldHandleReopen_hasVisibleWindows_(self, _app, _flag):
        self.owner.show_dashboard()
        return True

    @objc.IBAction
    def openDashboard_(self, _sender):
        self.owner.show_dashboard()

    @objc.IBAction
    def openPreferences_(self, _sender):
        self.owner.show_preferences()

    @objc.IBAction
    def toggleMeeting_(self, _sender):
        self.owner.toggle_meeting()

    @objc.IBAction
    def quitApp_(self, _sender):
        self.owner.quit()

    @objc.IBAction
    def copyRecentDictation_(self, sender):
        if self.owner._status_item is not None:
            self.owner._status_item.copy_recent_dictation(sender.tag())

    @objc.IBAction
    def copyRecentMeeting_(self, sender):
        if self.owner._status_item is not None:
            self.owner._status_item.copy_recent_meeting(sender.tag())

    @objc.IBAction
    def selectBackend_(self, sender):
        if self.owner._status_item is not None:
            self.owner._status_item.select_backend_for_tag(sender.tag())
