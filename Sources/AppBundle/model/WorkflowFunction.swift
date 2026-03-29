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

func getNextCalendarEvent(titleFilter: ((String) -> Bool)? = nil) async -> CalendarEvent? {
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

    let match = titleFilter.map { f in events.first { f($0.title ?? "") } } ?? events.first
    guard let next = match else { return nil }
    return CalendarEvent(
        title: next.title ?? "Untitled",
        startDate: next.startDate,
        endDate: next.endDate,
        location: next.location,
        notes: next.notes
    )
}

// MARK: - Reusable workflow helpers

/// Polls until a window with the given app ID appears and is assigned to a workspace.
@MainActor func awaitWindowByAppId(_ appId: KnownBundleId, timeout: Int = 20) async -> MacWindow? {
    for _ in 0..<timeout {
        if let window = MacWindow.allWindows.first(where: { $0.macApp.appId == appId && $0.nodeWorkspace != nil }) {
            return window
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
    return nil
}

/// Moves `windowB` into `windowA`'s workspace side by side (h_tiles) and focuses.
@MainActor func pairWindowsSideBySide(_ windowA: MacWindow, _ windowB: MacWindow) {
    guard let targetWs = windowA.nodeWorkspace else { return }
    let root = targetWs.rootTilingContainer
    if root.orientation != .h { root.changeOrientation(.h) }
    _ = moveWindowToWorkspace(windowB, targetWs, CmdIo(stdin: .emptyStdin), focusFollowsWindow: false, failIfNoop: false)
    _ = targetWs.focusWorkspace()
    windowA.nativeFocus()
    scheduleRefreshSession(.ax("workflow"))
}

@MainActor func setWorkflowDone() {
    TrayMenuModel.shared.workflowRunState = .done
    Task {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        TrayMenuModel.shared.workflowRunState = .idle
    }
}

// MARK: - Workflows

@MainActor func openNextMeeting() async {
    TrayMenuModel.shared.workflowRunState = .running
    guard let event = await getNextCalendarEvent(),
          let link = event.meetingLink, let url = URL(string: link) else {
        TrayMenuModel.shared.workflowRunState = .idle
        return
    }
    NSWorkspace.shared.open(url)
    setWorkflowDone()
}

@MainActor func openStandup() async {
    TrayMenuModel.shared.workflowRunState = .running

    guard let event = await getNextCalendarEvent(titleFilter: {
        let l = $0.lowercased(); return l.contains("standup") || l.contains("stand up")
    }), let link = event.meetingLink, let zoomURL = URL(string: link) else {
        TrayMenuModel.shared.workflowRunState = .idle
        return
    }

    // Open Jira first to capture the browser's bundle ID, then Zoom
    let browserApp = try? await NSWorkspace.shared.open(
        URL(string: "https://harrison-ai.atlassian.net/jira/for-you")!,
        configuration: NSWorkspace.OpenConfiguration()
    )
    NSWorkspace.shared.open(zoomURL)

    // Wait for Zoom to settle on its workspace, then move browser there
    guard let zoom = await awaitWindowByAppId(.zoom),
          let bid = browserApp?.bundleIdentifier,
          let browser = MacWindow.allWindows.filter({ $0.app.rawAppBundleId == bid }).max(by: { $0.windowId < $1.windowId })
    else {
        TrayMenuModel.shared.workflowRunState = .idle
        return
    }

    pairWindowsSideBySide(zoom, browser)
    setWorkflowDone()
}
