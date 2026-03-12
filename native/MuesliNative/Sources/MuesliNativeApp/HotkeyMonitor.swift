import AppKit
import ApplicationServices
import Foundation

final class HotkeyMonitor {
    var onPrepare: (() -> Void)?
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var prepareWorkItem: DispatchWorkItem?
    private var startWorkItem: DispatchWorkItem?
    private var leftCommandDown = false
    private var otherKeyPressed = false
    private var prepared = false
    private var active = false

    private let prepareDelay: TimeInterval = 0.15
    private let startDelay: TimeInterval = 0.25

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }

        let hasListenAccess = CGPreflightListenEventAccess()
        fputs("[hotkey] listen event access: \(hasListenAccess)\n", stderr)
        if !hasListenAccess {
            let requested = CGRequestListenEventAccess()
            fputs("[hotkey] requested listen event access: \(requested)\n", stderr)
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
            return event
        }

        if globalMonitor != nil || localMonitor != nil {
            fputs("[hotkey] event monitors started\n", stderr)
        } else {
            fputs("[hotkey] failed to start event monitors\n", stderr)
        }
    }

    func stop() {
        cancelTimers()
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
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
        globalMonitor != nil || localMonitor != nil
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            handleFlagsChanged(event)
        case .keyDown:
            handleKeyDown(event)
        default:
            break
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if keyCode == 55 {
            let isDown = flags.contains(.command)
            if isDown {
                if !leftCommandDown {
                    fputs("[hotkey] left command down\n", stderr)
                    leftCommandDown = true
                    otherKeyPressed = false
                    prepared = false
                    scheduleTimers()
                }
            } else {
                fputs("[hotkey] left command up\n", stderr)
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
        } else if keyCode == 54, !flags.contains(.command), leftCommandDown {
            fputs("[hotkey] canceled by right command\n", stderr)
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

    private func handleKeyDown(_ event: NSEvent) {
        if leftCommandDown {
            let keyCode = event.keyCode
            if keyCode != 55 && keyCode != 54 {
                fputs("[hotkey] canceled by other key\n", stderr)
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
            fputs("[hotkey] prepared\n", stderr)
            self.onPrepare?()
        }
        let start = DispatchWorkItem { [weak self] in
            guard let self, self.leftCommandDown, !self.otherKeyPressed, !self.active else { return }
            self.active = true
            fputs("[hotkey] start\n", stderr)
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
