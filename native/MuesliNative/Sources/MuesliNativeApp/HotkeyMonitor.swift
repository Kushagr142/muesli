import ApplicationServices
import Foundation

final class HotkeyMonitor {
    var onPrepare: (() -> Void)?
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var prepareWorkItem: DispatchWorkItem?
    private var startWorkItem: DispatchWorkItem?
    private var leftCommandDown = false
    private var otherKeyPressed = false
    private var prepared = false
    private var active = false

    private let prepareDelay: TimeInterval = 0.15
    private let startDelay: TimeInterval = 0.25

    func start() {
        guard eventTap == nil else { return }

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handle(eventType: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            fputs("[hotkey] failed to create event tap\n", stderr)
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        cancelTimers()
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        leftCommandDown = false
        otherKeyPressed = false
        prepared = false
        active = false
    }

    func restart() {
        stop()
        start()
    }

    var isRunning: Bool {
        eventTap != nil
    }

    private func handle(eventType: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch eventType {
        case .flagsChanged:
            handleFlagsChanged(event)
        case .keyDown:
            handleKeyDown(event)
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if keyCode == 55 {
            let isDown = flags.contains(.maskCommand)
            if isDown {
                if !leftCommandDown {
                    leftCommandDown = true
                    otherKeyPressed = false
                    prepared = false
                    scheduleTimers()
                }
            } else {
                leftCommandDown = false
                cancelTimers()
                if active {
                    active = false
                    onStop?()
                } else if prepared {
                    prepared = false
                    onCancel?()
                }
            }
        } else if keyCode == 54, !flags.contains(.maskCommand), leftCommandDown {
            otherKeyPressed = true
            cancelTimers()
            if active {
                active = false
                onStop?()
            } else if prepared {
                prepared = false
                onCancel?()
            }
        }
    }

    private func handleKeyDown(_ event: CGEvent) {
        if leftCommandDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode != 55 && keyCode != 54 {
                otherKeyPressed = true
                cancelTimers()
                if active {
                    active = false
                    onStop?()
                } else if prepared {
                    prepared = false
                    onCancel?()
                }
            }
        }
    }

    private func scheduleTimers() {
        let prepare = DispatchWorkItem { [weak self] in
            guard let self, self.leftCommandDown, !self.otherKeyPressed, !self.prepared else { return }
            self.prepared = true
            self.onPrepare?()
        }
        let start = DispatchWorkItem { [weak self] in
            guard let self, self.leftCommandDown, !self.otherKeyPressed, !self.active else { return }
            self.active = true
            self.onStart?()
        }
        prepareWorkItem = prepare
        startWorkItem = start
        DispatchQueue.main.asyncAfter(deadline: .now() + prepareDelay, execute: prepare)
        DispatchQueue.main.asyncAfter(deadline: .now() + startDelay, execute: start)
    }

    private func cancelTimers() {
        prepareWorkItem?.cancel()
        startWorkItem?.cancel()
        prepareWorkItem = nil
        startWorkItem = nil
    }
}
