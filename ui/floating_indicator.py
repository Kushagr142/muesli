from __future__ import annotations

from Cocoa import (
    NSBackingStoreBuffered,
    NSColor,
    NSFont,
    NSMakeRect,
    NSPanel,
    NSScreen,
    NSTextField,
    NSView,
    NSWindowCollectionBehaviorCanJoinAllSpaces,
    NSWindowCollectionBehaviorFullScreenAuxiliary,
    NSWindowCollectionBehaviorStationary,
    NSFloatingWindowLevel,
    NSWindowStyleMaskBorderless,
)
import objc
from PyObjCTools import AppHelper


STATE_STYLES = {
    "idle": {
        "icon": "🎤",
        "title": "",
        "size": (58, 38),
        "background": (0.10, 0.10, 0.12, 0.66),
        "border": (1.0, 1.0, 1.0, 0.18),
        "icon_color": (1.0, 1.0, 1.0, 0.92),
        "text_color": (1.0, 1.0, 1.0, 0.92),
    },
    "listening": {
        "icon": "🎤",
        "title": "Listening",
        "size": (164, 46),
        "background": (0.83, 0.18, 0.22, 0.94),
        "border": (1.0, 1.0, 1.0, 0.24),
        "icon_color": (1.0, 1.0, 1.0, 1.0),
        "text_color": (1.0, 1.0, 1.0, 1.0),
    },
    "transcribing": {
        "icon": "✍️",
        "title": "Transcribing",
        "size": (182, 46),
        "background": (0.83, 0.60, 0.11, 0.94),
        "border": (1.0, 1.0, 1.0, 0.24),
        "icon_color": (0.10, 0.08, 0.05, 0.95),
        "text_color": (0.10, 0.08, 0.05, 0.95),
    },
    "meeting": {
        "icon": "📝",
        "title": "Meeting",
        "size": (146, 46),
        "background": (0.14, 0.62, 0.38, 0.94),
        "border": (1.0, 1.0, 1.0, 0.24),
        "icon_color": (1.0, 1.0, 1.0, 1.0),
        "text_color": (1.0, 1.0, 1.0, 1.0),
    },
    "processing": {
        "icon": "⚙️",
        "title": "Processing",
        "size": (170, 46),
        "background": (0.17, 0.28, 0.74, 0.94),
        "border": (1.0, 1.0, 1.0, 0.24),
        "icon_color": (1.0, 1.0, 1.0, 1.0),
        "text_color": (1.0, 1.0, 1.0, 1.0),
    },
}


def _ns_color(rgba: tuple[float, float, float, float]):
    return NSColor.colorWithRed_green_blue_alpha_(*rgba)


class IndicatorView(NSView):
    def initWithFrame_(self, frame):
        self = objc.super(IndicatorView, self).initWithFrame_(frame)
        if self is None:
            return None

        self.setWantsLayer_(True)

        self.icon_label = self._make_label(frame, 18, True)
        self.text_label = self._make_label(frame, 13, False)
        self.addSubview_(self.icon_label)
        self.addSubview_(self.text_label)
        self.apply_style("idle")
        return self

    def _make_label(self, frame, font_size: int, bold: bool):
        label = NSTextField.alloc().initWithFrame_(frame)
        label.setBezeled_(False)
        label.setDrawsBackground_(False)
        label.setEditable_(False)
        label.setSelectable_(False)
        label.setBordered_(False)
        label.setAlignment_(1)
        font = NSFont.boldSystemFontOfSize_(font_size) if bold else NSFont.systemFontOfSize_(font_size)
        label.setFont_(font)
        return label

    def apply_style(self, state: str):
        style = STATE_STYLES.get(state, STATE_STYLES["idle"])
        width, height = style["size"]

        layer = self.layer()
        layer.setCornerRadius_(height / 2)
        layer.setBackgroundColor_(_ns_color(style["background"]).CGColor())
        layer.setBorderWidth_(1.0)
        layer.setBorderColor_(_ns_color(style["border"]).CGColor())

        self.icon_label.setStringValue_(style["icon"])
        self.icon_label.setTextColor_(_ns_color(style["icon_color"]))
        self.icon_label.setFrame_(NSMakeRect(12, 9, 24, max(height - 18, 18)))

        self.text_label.setStringValue_(style["title"])
        self.text_label.setTextColor_(_ns_color(style["text_color"]))
        self.text_label.setHidden_(not bool(style["title"]))
        self.text_label.setFrame_(NSMakeRect(40, 12, max(width - 52, 0), max(height - 20, 16)))


class FloatingIndicator:
    """Small always-on-top status pill anchored to the right edge of the screen."""

    def __init__(self):
        self.panel: NSPanel | None = None
        self.view: IndicatorView | None = None
        self.state = "idle"
        AppHelper.callAfter(self._create_panel)

    def _create_panel(self):
        if self.panel is not None:
            return

        width, height = STATE_STYLES["idle"]["size"]
        frame = self._frame_for_size(width, height)
        self.panel = NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(
            frame,
            NSWindowStyleMaskBorderless,
            NSBackingStoreBuffered,
            False,
        )
        self.panel.setLevel_(NSFloatingWindowLevel)
        self.panel.setOpaque_(False)
        self.panel.setBackgroundColor_(NSColor.clearColor())
        self.panel.setHasShadow_(True)
        self.panel.setHidesOnDeactivate_(False)
        self.panel.setIgnoresMouseEvents_(True)
        self.panel.setMovableByWindowBackground_(False)
        self.panel.setCollectionBehavior_(
            NSWindowCollectionBehaviorCanJoinAllSpaces
            | NSWindowCollectionBehaviorFullScreenAuxiliary
            | NSWindowCollectionBehaviorStationary
        )

        self.view = IndicatorView.alloc().initWithFrame_(NSMakeRect(0, 0, width, height))
        self.panel.setContentView_(self.view)
        self.panel.orderFrontRegardless()
        self._apply_state(self.state)

    def _frame_for_size(self, width: float, height: float):
        screen = NSScreen.mainScreen()
        if screen is None:
            return NSMakeRect(0, 0, width, height)
        visible = screen.visibleFrame()
        x = visible.origin.x + visible.size.width - width - 18
        y = visible.origin.y + (visible.size.height * 0.56) - (height / 2)
        return NSMakeRect(x, y, width, height)

    def _apply_state(self, state: str):
        self.state = state if state in STATE_STYLES else "idle"
        if self.panel is None or self.view is None:
            self._create_panel()
            return

        style = STATE_STYLES[self.state]
        width, height = style["size"]
        self.view.setFrame_(NSMakeRect(0, 0, width, height))
        self.view.apply_style(self.state)
        self.panel.setFrame_display_(
            self._frame_for_size(width, height),
            True,
        )
        self.panel.setAlphaValue_(0.82 if self.state == "idle" else 1.0)
        self.panel.orderFrontRegardless()

    def set_state(self, state: str):
        AppHelper.callAfter(self._apply_state, state)

    def close(self):
        if self.panel is not None:
            AppHelper.callAfter(self.panel.close)
