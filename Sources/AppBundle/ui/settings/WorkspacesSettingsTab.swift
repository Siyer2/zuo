import Common
import SwiftUI

struct WorkspacesSettingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var newWorkspaceName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Persistent Workspaces")
                    .font(.headline)
                Spacer()
                Text("Workspaces that stay alive even when empty")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            // Workspace list
            List {
                ForEach(viewModel.persistentWorkspaces, id: \.self) { workspace in
                    HStack {
                        Text(workspace)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) {
                            viewModel.persistentWorkspaces.removeAll { $0 == workspace }
                            viewModel.markChanged()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove { from, to in
                    viewModel.persistentWorkspaces.move(fromOffsets: from, toOffset: to)
                    viewModel.markChanged()
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider()

            // Add workspace
            HStack {
                TextField("Workspace name", text: $newWorkspaceName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .onSubmit { addWorkspace() }

                Button("Add") { addWorkspace() }
                    .disabled(newWorkspaceName.isEmpty)

                Spacer()

                Text("\(viewModel.persistentWorkspaces.count) workspaces")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .padding()
        }
    }

    private func addWorkspace() {
        let name = newWorkspaceName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !viewModel.persistentWorkspaces.contains(name) else { return }
        viewModel.persistentWorkspaces.append(name)
        newWorkspaceName = ""
        viewModel.markChanged()
    }
}
