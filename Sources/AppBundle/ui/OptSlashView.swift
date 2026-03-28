import AppKit
import SwiftUI

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
        WorkflowStore.shared.load()
        let view = OptSlashView(
            workflows: WorkflowStore.shared.workflows,
            onSubmit: { workflow in
                print(workflow.name)
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
                        .background(index == selectedIndex ? Color.accentColor.opacity(0.2) : .clear)
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
