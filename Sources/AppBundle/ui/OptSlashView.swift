import AppKit
import SwiftUI

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
    override public func cancelOperation(_ sender: Any?) { close() }

    @MainActor func toggle() {
        if isVisible {
            close()
            return
        }
        let view = OptSlashView(
            workflows: allWorkflows,
            onSubmit: { workflow in
                self.close()
                Task { await workflow.run() }
            },
            onCancel: { self.close() }
        )
        contentView = NSHostingView(rootView: view.ignoresSafeArea())
        if let screen = NSScreen.main {
            let x = screen.frame.midX - frame.width / 2
            let y = screen.frame.midY + screen.frame.height * 0.2
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        // Agent apps (LSUIElement) are never the active application.
        // SwiftUI gesture recognizers on a nonActivatingPanel require the
        // owning app to be active to deliver mouse events — without this,
        // onTapGesture silently swallows clicks in codesigned/DMG builds.
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        orderFront(nil)
        makeKey()
    }

    @MainActor func showError(_ error: WorkflowError) {
        let view = OptSlashErrorView(
            message: error.message,
            settingsURL: error.settingsURL,
            onDismiss: { self.close() }
        )
        contentView = NSHostingView(rootView: view.ignoresSafeArea())
        let fitSize = contentView!.fittingSize
        setContentSize(NSSize(width: max(fitSize.width, 480), height: fitSize.height))
        if let screen = NSScreen.main {
            let x = screen.frame.midX - frame.width / 2
            let y = screen.frame.midY + screen.frame.height * 0.2
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        orderFront(nil)
        makeKey()
        // Auto-dismiss only if there's no action for the user to click
        if error.settingsURL == nil {
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if self.isVisible { self.close() }
            }
        }
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
                    placeholder: "Run a workflow",
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
                            InfoButton(description: wf.description)
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

// MARK: - Error View

struct OptSlashErrorView: View {
    let message: String
    let settingsURL: URL?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.yellow)
            Text(message)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let settingsURL {
                Text("Open System Settings")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NSWorkspace.shared.open(settingsURL)
                        onDismiss()
                    }
            }
            Text("esc")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08))
                .cornerRadius(4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Info Button

private struct InfoButton: View {
    let description: String
    @State private var isHovering = false

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 14))
            .foregroundStyle(isHovering ? .secondary : .tertiary)
            .onHover { isHovering = $0 }
            .popover(isPresented: $isHovering, arrowEdge: .trailing) {
                Text(description)
                    .font(.system(size: 12))
                    .padding(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 250)
            }
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
