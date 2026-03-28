import Foundation

struct OptSlashWorkflow: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var prompt: String

    init(name: String, prompt: String) {
        self.id = UUID()
        self.name = name
        self.prompt = prompt
    }
}

@MainActor
final class PermissionStore {
    static let shared = PermissionStore()
    private(set) var allowed: [String] = []

    private var fileUrl: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/zuo/memory")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "claude-permissions.json")
    }

    var filePath: String {
        let url = fileUrl
        if !FileManager.default.fileExists(atPath: url.path) { save() }
        return url.path
    }

    func load() {
        guard let data = try? Data(contentsOf: fileUrl),
              let root = try? JSONDecoder().decode(PermissionFile.self, from: data)
        else { return }
        allowed = root.permissions.allow
    }

    func addPermission(_ key: String) {
        load()
        guard !allowed.contains(key) else { return }
        allowed.append(key)
        save()
    }

    private func save() {
        let file = PermissionFile(permissions: PermissionFile.Permissions(allow: allowed))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(file) else { return }
        try? data.write(to: fileUrl)
    }

    private struct PermissionFile: Codable {
        struct Permissions: Codable { var allow: [String] }
        var permissions: Permissions
    }
}

@MainActor
final class WorkflowStore {
    static let shared = WorkflowStore()
    private(set) var workflows: [OptSlashWorkflow] = []

    private var fileUrl: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/zuo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "workflows.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: fileUrl),
              let decoded = try? JSONDecoder().decode([OptSlashWorkflow].self, from: data)
        else { return }
        workflows = decoded
    }

    func add(_ workflow: OptSlashWorkflow) {
        workflows.append(workflow)
        save()
    }

    func update(_ workflow: OptSlashWorkflow) {
        guard let i = workflows.firstIndex(where: { $0.id == workflow.id }) else { return }
        workflows[i] = workflow
        save()
    }

    func delete(id: UUID) {
        workflows.removeAll { $0.id == id }
        save()
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(workflows) else { return }
        try? data.write(to: fileUrl)
    }
}
