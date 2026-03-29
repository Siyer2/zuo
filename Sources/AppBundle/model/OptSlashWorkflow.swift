import Foundation

struct OptSlashWorkflow: Identifiable {
    let id: String
    let name: String
    let description: String
    let run: @MainActor () async -> Void
}

let allWorkflows: [OptSlashWorkflow] = [
    OptSlashWorkflow(
        id: "meeting",
        name: "Next Meeting",
        description: "Opens the Zoom/Teams link for your next calendar event",
        run: { await openNextMeeting() }
    ),
]
