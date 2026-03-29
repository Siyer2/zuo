import EventKit
import AppKit

struct CalendarEvent {
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let notes: String?

    var meetingLink: String? {
        let pattern = try! NSRegularExpression(pattern: "https?://[^\\s\"<>]*(?:zoom\\.us|teams\\.microsoft\\.com)[^\\s\"<>]*")
        for text in [location, notes].compactMap({ $0 }) {
            let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
            if let m = matches.first, let range = Range(m.range, in: text) {
                return String(text[range])
            }
        }
        return nil
    }
}

func getNextCalendarEvent() async -> CalendarEvent? {
    let store = EKEventStore()
    let granted: Bool
    if #available(macOS 14, *) {
        granted = (try? await store.requestFullAccessToEvents()) ?? false
    } else {
        granted = await withCheckedContinuation { cont in
            store.requestAccess(to: .event) { g, _ in cont.resume(returning: g) }
        }
    }
    guard granted else { return nil }

    let now = Date()
    let end = Calendar.current.date(byAdding: .day, value: 7, to: now)!
    let events = store.events(matching: store.predicateForEvents(withStart: now, end: end, calendars: nil))
        .sorted { $0.startDate < $1.startDate }

    guard let next = events.first else { return nil }
    return CalendarEvent(
        title: next.title ?? "Untitled",
        startDate: next.startDate,
        endDate: next.endDate,
        location: next.location,
        notes: next.notes
    )
}

@MainActor func openNextMeeting() async {
    TrayMenuModel.shared.workflowRunState = .running
    guard let event = await getNextCalendarEvent() else {
        TrayMenuModel.shared.workflowRunState = .idle
        return
    }
    if let link = event.meetingLink, let url = URL(string: link) {
        NSWorkspace.shared.open(url)
    }
    TrayMenuModel.shared.workflowRunState = .done
    Task {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        TrayMenuModel.shared.workflowRunState = .idle
    }
}
