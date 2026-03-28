import AppKit
import SwiftUI

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
        let view = OptSlashView(onSubmit: { text in
            print(text)
            self.close()
        }, onCancel: {
            self.close()
        })
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
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
            AutoFocusTextField(
                placeholder: "Zuo Workflow Search",
                onSubmit: onSubmit,
                onCancel: onCancel
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct AutoFocusTextField: NSViewRepresentable {
    let placeholder: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 22, weight: .light)
        field.cell?.sendsActionOnEndEditing = false
        // Schedule focus for after the view is installed in the window
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: AutoFocusTextField
        init(_ parent: AutoFocusTextField) { self.parent = parent }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit(control.stringValue)
                return true
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

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
