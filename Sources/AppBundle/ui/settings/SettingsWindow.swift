import Common
import SwiftUI

public let settingsWindowId = "\(zuoAppName).settingsView"

@MainActor
public func getSettingsWindow(viewModel: SettingsViewModel) -> some Scene {
    SwiftUI.Window("\(zuoAppName) Settings", id: settingsWindowId) {
        SettingsView(viewModel: viewModel)
            .onAppear {
                NSApp.setActivationPolicy(.accessory)
                viewModel.load()
            }
    }
    .windowResizability(.contentMinSize)
}

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var selectedTab: SettingsTab = .general
    @State private var showRevertAlert = false
    @State private var showCommentWarning = false

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case gaps = "Gaps"
        case keybindings = "Keybindings"
        case workspaces = "Workspaces"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab content
            TabView(selection: $selectedTab) {
                GeneralSettingsTab(viewModel: viewModel)
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(SettingsTab.general)

                GapsSettingsTab(viewModel: viewModel)
                    .tabItem { Label("Gaps", systemImage: "rectangle.split.3x3") }
                    .tag(SettingsTab.gaps)

                KeybindingsSettingsTab(viewModel: viewModel)
                    .tabItem { Label("Keybindings", systemImage: "keyboard") }
                    .tag(SettingsTab.keybindings)

                WorkspacesSettingsTab(viewModel: viewModel)
                    .tabItem { Label("Workspaces", systemImage: "square.grid.3x3") }
                    .tag(SettingsTab.workspaces)
            }

            Divider()

            // Bottom toolbar
            HStack {
                Button("Open in Editor") {
                    openConfigInEditor()
                }

                Spacer()

                if viewModel.hasUnsavedChanges {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                    Text("Unsaved changes")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button("Revert") {
                    if viewModel.hasUnsavedChanges {
                        showRevertAlert = true
                    } else {
                        viewModel.revert()
                    }
                }
                .disabled(!viewModel.hasUnsavedChanges)

                Button("Save & Apply") {
                    viewModel.save()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!viewModel.hasUnsavedChanges)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 680, minHeight: 500)
        .alert("Revert Changes?", isPresented: $showRevertAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Revert", role: .destructive) { viewModel.revert() }
        } message: {
            Text("This will discard all unsaved changes and reload from the config file.")
        }
        .alert("Config File Notice", isPresented: $showCommentWarning) {
            Button("OK") { viewModel.showCommentWarning = false }
        } message: {
            Text("Saving from the Settings UI will reformat your config file. Comments in the TOML file may be removed.")
        }
        .onChange(of: viewModel.showCommentWarning) { show in
            if show { showCommentWarning = true }
        }
    }

    private func openConfigInEditor() {
        let editor = getTextEditorToOpenConfig()
        if let url = viewModel.configUrl {
            url.open(with: editor)
        }
    }
}
