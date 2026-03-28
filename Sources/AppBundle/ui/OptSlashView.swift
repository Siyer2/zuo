import AppKit
import SwiftUI

private let structuredOutputInstruction = """

    IMPORTANT: Respond with ONLY a JSON object (no markdown fences, no extra text).
    Schema: {"status":"success"|"error"|"missing_connector", "message":"...", "connector_name":"...", "connector_instructions":"...", "permission_key":"..."}
    - "success": workflow completed, put result summary in message.
    - "error": something went wrong, put error details in message.
    - "missing_connector": a connector/integration permission is required. Set connector_name, connector_instructions, and permission_key (the exact string to add to settings.local.json permissions.allow, e.g. "WebFetch(domain:example.com)" or "Bash").
    """

@MainActor private var lastWorkflowPrompt: String?

@MainActor func runClaudeWorkflow(_ prompt: String) {
    let claudePath = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".local/bin/claude").path
    guard FileManager.default.isExecutableFile(atPath: claudePath) else {
        showWorkflowError(
            "Claude Code is not installed.\nInstall it from https://docs.anthropic.com/en/docs/claude-code"
        )
        return
    }
    print("Sending prompt", prompt)
    lastWorkflowPrompt = prompt
    TrayMenuModel.shared.workflowRunState = .running
    let model = "claude-haiku-4-5-20251001"
    let settingsPath = PermissionStore.shared.filePath.shellEscaped
    let fullPrompt = (prompt + structuredOutputInstruction).shellEscaped
    let process = Process()
    process.executableURL = URL(filePath: "/bin/zsh")
    process.arguments = [
        "-c",
        "export PATH=\"$HOME/.local/bin:$PATH\" && claude --settings \(settingsPath) -p \(fullPrompt) --model \(model)",
    ]
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    do { try process.run() } catch {
        showWorkflowError("Failed to launch Claude Code: \(error.localizedDescription)")
        return
    }
    DispatchQueue.global().async {
        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err =
            String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            ?? ""
        Task { @MainActor in
            if !out.isEmpty { print("stdout:", out) }
            if !err.isEmpty { print("stderr:", err) }
            handleWorkflowOutput(out, stderr: err)
        }
    }
}

@MainActor private func handleWorkflowOutput(_ output: String, stderr: String) {
    guard let result = parseWorkflowResult(output) else {
        let detail = stderr.isEmpty ? String(output.prefix(200)) : String(stderr.prefix(200))
        showWorkflowError(detail.isEmpty ? "No response from Claude Code." : detail)
        return
    }
    switch result.status {
    case .success:
        markWorkflowDone()
    case .error:
        showWorkflowError(result.message)
    case .missing_connector:
        let name = result.connector_name ?? "Unknown connector"
        let key = result.permission_key
        TrayMenuModel.shared.workflowRunState = .idle
        PermissionPromptPanel.shared.show(connectorName: name, permissionKey: key) {
            guard let key else { return }
            PermissionStore.shared.addPermission(key)
            if let prompt = lastWorkflowPrompt { runClaudeWorkflow(prompt) }
        }
    }
}

private func parseWorkflowResult(_ output: String) -> WorkflowResult? {
    if let data = output.data(using: .utf8),
        let result = try? JSONDecoder().decode(WorkflowResult.self, from: data)
    {
        return result
    }
    guard let start = output.firstIndex(of: "{"),
        let end = output.lastIndex(of: "}"), start < end
    else { return nil }
    let json = output[start...end]
    guard let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(WorkflowResult.self, from: data)
}

@MainActor private func markWorkflowDone() {
    TrayMenuModel.shared.workflowRunState = .done
    Task {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        TrayMenuModel.shared.workflowRunState = .idle
    }
}

@MainActor private func showWorkflowError(_ message: String) {
    TrayMenuModel.shared.workflowRunState = .idle
    WorkflowErrorPanel.shared.show(message: message)
}

// MARK: - Permission Prompt Panel

final class PermissionPromptPanel: NSPanel {
    @MainActor static let shared = PermissionPromptPanel()

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 0),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .floating
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    @MainActor func show(
        connectorName: String, permissionKey: String?, onAllow: @escaping () -> Void
    ) {
        let view = PermissionPromptView(
            connectorName: connectorName,
            permissionKey: permissionKey,
            onAllow: {
                onAllow()
                self.close()
            },
            onDeny: { self.close() }
        )
        let hostingView = NSHostingView(rootView: view.ignoresSafeArea())
        hostingView.frame.size = hostingView.fittingSize
        contentView = hostingView
        setContentSize(hostingView.fittingSize)
        if let screen = NSScreen.main {
            setFrameOrigin(
                NSPoint(
                    x: screen.frame.midX - frame.width / 2,
                    y: screen.frame.midY - frame.height / 2))
        }
        orderFront(nil)
        makeKey()
    }
}

struct PermissionPromptView: View {
    let connectorName: String
    let permissionKey: String?
    let onAllow: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("Permission Required")
                .font(.system(size: 16, weight: .semibold))
            Text("\(connectorName) needs access to run this workflow.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let key = permissionKey {
                Text(key)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 12) {
                Button("Deny") { onDeny() }
                    .keyboardShortcut(.cancelAction)
                Button("Allow") { onAllow() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Workflow Error Panel

final class WorkflowErrorPanel: NSPanel {
    @MainActor static let shared = WorkflowErrorPanel()

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 0),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .floating
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    @MainActor func show(message: String) {
        let view = WorkflowErrorView(message: message, onDismiss: { self.close() })
        let hostingView = NSHostingView(rootView: view.ignoresSafeArea())
        hostingView.frame.size = hostingView.fittingSize
        contentView = hostingView
        setContentSize(hostingView.fittingSize)
        if let screen = NSScreen.main {
            let x = screen.frame.midX - frame.width / 2
            let y = screen.frame.midY - frame.height / 2
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        orderFront(nil)
        makeKey()
    }
}

struct WorkflowErrorView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.yellow)
            Text("Workflow Error")
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("OK") { onDismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(width: 400)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

extension String {
    fileprivate var shellEscaped: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - Workflow Management Panel

public final class OptSlashAddWorkflowPanel: NSPanel {
    @MainActor static let shared = OptSlashAddWorkflowPanel()

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .floating
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { true }

    @MainActor func show() {
        WorkflowStore.shared.load()
        let view = ManageWorkflowsView(onDone: { self.close() })
        contentView = NSHostingView(rootView: view.ignoresSafeArea())
        if let screen = NSScreen.main {
            let x = screen.frame.midX - frame.width / 2
            let y = screen.frame.midY - frame.height / 2
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        orderFront(nil)
        makeKey()
    }
}

struct ManageWorkflowsView: View {
    let onDone: () -> Void

    @State private var workflows: [OptSlashWorkflow] = WorkflowStore.shared.workflows
    @State private var newName = ""
    @State private var newPrompt = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("OptSlash Workflows")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Done", action: onDone)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            if workflows.isEmpty {
                Text("No workflows yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach($workflows) { $wf in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("Name", text: $wf.name)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 14, weight: .medium))
                                TextField("Prompt", text: $wf.prompt)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                WorkflowStore.shared.delete(id: wf.id)
                                workflows = WorkflowStore.shared.workflows
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        .onChange(of: wf) { _ in WorkflowStore.shared.update(wf) }
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                TextField("Prompt", text: $newPrompt)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                Button("Add") {
                    WorkflowStore.shared.add(OptSlashWorkflow(name: newName, prompt: newPrompt))
                    workflows = WorkflowStore.shared.workflows
                    newName = ""
                    newPrompt = ""
                }
                .disabled(newName.isEmpty || newPrompt.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 520, height: 400)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Claude Notice

private func claudeNoticeUrl() -> URL {
    FileManager.default.homeDirectoryForCurrentUser.appending(
        path: ".config/zuo/has-seen-claude-notice")
}

private func hasSeenClaudeNotice() -> Bool {
    FileManager.default.fileExists(atPath: claudeNoticeUrl().path)
}

private func markClaudeNoticeSeen() {
    let url = claudeNoticeUrl()
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: nil)
}

final class ClaudeNoticePanel: NSPanel {
    @MainActor static let shared = ClaudeNoticePanel()

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 0),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .floating
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    @MainActor func show(onAcknowledge: @escaping () -> Void) {
        let view = ClaudeNoticeView(onAcknowledge: {
            onAcknowledge()
            self.close()
        })
        let hostingView = NSHostingView(rootView: view.ignoresSafeArea())
        hostingView.frame.size = hostingView.fittingSize
        contentView = hostingView
        setContentSize(hostingView.fittingSize)
        if let screen = NSScreen.main {
            setFrameOrigin(
                NSPoint(
                    x: screen.frame.midX - frame.width / 2,
                    y: screen.frame.midY - frame.height / 2))
        }
        orderFront(nil)
        makeKey()
    }
}

struct ClaudeNoticeView: View {
    let onAcknowledge: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 32))
                .foregroundStyle(.blue)
            Text("OptSlash uses Claude Code")
                .font(.system(size: 16, weight: .semibold))
            Text(
                "Workflows run using the Claude Code CLI installed on your machine. Make sure it's set up and authenticated."
            )
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            Button("Got it") { onAcknowledge() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(width: 400)
        .background(VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - OptSlash Panel (fuzzy search workflows)

private let maxVisibleWorkflows = 5

public final class OptSlashPanel: NSPanel {
    @MainActor static let shared = OptSlashPanel()

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 52),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior.insert(.fullScreenAuxiliary)
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { true }

    @MainActor func toggle() {
        if isVisible {
            close()
            return
        }
        if !hasSeenClaudeNotice() {
            ClaudeNoticePanel.shared.show {
                markClaudeNoticeSeen()
                self.showOptSlash()
            }
            return
        }
        showOptSlash()
    }

    @MainActor private func showOptSlash() {
        WorkflowStore.shared.load()
        let view = OptSlashView(
            workflows: WorkflowStore.shared.workflows,
            onSubmit: { workflow in
                print(workflow.name)
                runClaudeWorkflow(workflow.prompt)
                self.close()
            },
            onCancel: { self.close() }
        )
        contentView = NSHostingView(rootView: view.ignoresSafeArea())
        if let screen = NSScreen.main {
            let x = screen.frame.midX - frame.width / 2
            let y = screen.frame.midY + screen.frame.height * 0.2
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        orderFront(nil)
        makeKey()
    }
}

struct OptSlashView: View {
    let workflows: [OptSlashWorkflow]
    let onSubmit: (OptSlashWorkflow) -> Void
    let onCancel: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0

    var filtered: [OptSlashWorkflow] {
        let matches = query.isEmpty ? workflows : workflows.filter { fuzzyMatch(query, $0.name) }
        return Array(matches.prefix(maxVisibleWorkflows))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "bolt")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.secondary)
                AutoFocusTextField(
                    placeholder: "Run an OptSlash workflow",
                    onSubmit: { _ in submitSelected() },
                    onChange: { text in
                        query = text
                        selectedIndex = 0
                    },
                    onCancel: onCancel,
                    onMoveUp: { selectedIndex = max(0, selectedIndex - 1) },
                    onMoveDown: { selectedIndex = min(filtered.count - 1, selectedIndex + 1) }
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if !filtered.isEmpty {
                Divider().padding(.horizontal, 8)
                VStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, wf in
                        HStack {
                            Text(wf.name)
                                .font(.system(size: 16, weight: .light))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            index == selectedIndex ? Color.accentColor.opacity(0.2) : .clear
                        )
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onTapGesture { onSubmit(wf) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func submitSelected() {
        guard !filtered.isEmpty, filtered.indices.contains(selectedIndex) else { return }
        onSubmit(filtered[selectedIndex])
    }
}

// MARK: - Fuzzy match

func fuzzyMatch(_ query: String, _ candidate: String) -> Bool {
    var qi = query.lowercased().startIndex
    let ql = query.lowercased()
    let cl = candidate.lowercased()
    for char in cl {
        guard qi < ql.endIndex else { return true }
        if char == ql[qi] { qi = ql.index(after: qi) }
    }
    return qi == ql.endIndex
}

// MARK: - AutoFocusTextField

struct AutoFocusTextField: NSViewRepresentable {
    let placeholder: String
    let onSubmit: (String) -> Void
    let onChange: (String) -> Void
    let onCancel: () -> Void
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 22, weight: .light)
        field.cell?.sendsActionOnEndEditing = false
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: AutoFocusTextField
        init(_ parent: AutoFocusTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.onChange(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector)
            -> Bool
        {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit(control.stringValue)
                return true
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            if selector == #selector(NSResponder.moveUp(_:)) {
                parent.onMoveUp?()
                return true
            }
            if selector == #selector(NSResponder.moveDown(_:)) {
                parent.onMoveDown?()
                return true
            }
            return false
        }
    }
}

// MARK: - Visual Effect

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
