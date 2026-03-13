import EventKit
import Foundation

struct UpcomingMeetingEvent {
    let id: String
    let title: String
    let startDate: Date
}

final class CalendarMonitor {
    private let store = EKEventStore()
    private var timer: Timer?
    private var notifiedEvents = Set<String>()
    var onMeetingSoon: ((UpcomingMeetingEvent) -> Void)?

    func start() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            guard granted, let self else { return }
            DispatchQueue.main.async {
                self.checkMeetings()
                self.timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                    self?.checkMeetings()
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkMeetings() {
        let now = Date()
        let end = now.addingTimeInterval(5 * 60)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        for event in events {
            guard let eventID = event.eventIdentifier, !notifiedEvents.contains(eventID) else {
                continue
            }
            notifiedEvents.insert(eventID)
            onMeetingSoon?(UpcomingMeetingEvent(
                id: eventID,
                title: event.title ?? "Meeting",
                startDate: event.startDate
            ))
        }
    }
}
