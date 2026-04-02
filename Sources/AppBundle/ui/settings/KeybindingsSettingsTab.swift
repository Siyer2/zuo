import Common
import SwiftUI

struct KeybindingsSettingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var selectedModeIndex: Int = 0
    @State private var searchText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Mode selector
            HStack {
                Picker("Mode", selection: $selectedModeIndex) {
                    ForEach(viewModel.modes.indices, id: \.self) { index in
                        Text(viewModel.modes[index].name).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)

                Spacer()

                Button {
                    addMode()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add binding mode")
            }
            .padding()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter bindings...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.controlBackgroundColor))

            Divider()

            // Bindings table
            if selectedModeIndex < viewModel.modes.count {
                let filteredBindings = filteredBindings()
                if filteredBindings.isEmpty {
                    VStack {
                        Spacer()
                        Text("No bindings found")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(filteredBindings) { binding in
                            if let bindingIndex = viewModel.modes[selectedModeIndex].bindings.firstIndex(where: { $0.id == binding.id }) {
                                bindingRow(modeIndex: selectedModeIndex, bindingIndex: bindingIndex)
                            }
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }

            Divider()

            // Add binding button
            HStack {
                Button {
                    addBinding()
                } label: {
                    Label("Add Binding", systemImage: "plus")
                }
                Spacer()
                Text("\(currentBindingsCount) bindings")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .padding()
        }
    }

    private var currentBindingsCount: Int {
        guard selectedModeIndex < viewModel.modes.count else { return 0 }
        return viewModel.modes[selectedModeIndex].bindings.count
    }

    private func filteredBindings() -> [EditableBinding] {
        guard selectedModeIndex < viewModel.modes.count else { return [] }
        let bindings = viewModel.modes[selectedModeIndex].bindings
        if searchText.isEmpty { return bindings }
        let query = searchText.lowercased()
        return bindings.filter {
            $0.keyCombo.lowercased().contains(query) || $0.command.lowercased().contains(query)
        }
    }

    @ViewBuilder
    private func bindingRow(modeIndex: Int, bindingIndex: Int) -> some View {
        HStack(spacing: 12) {
            // Key combo
            TextField("Key combo", text: Binding(
                get: { viewModel.modes[modeIndex].bindings[bindingIndex].keyCombo },
                set: {
                    viewModel.modes[modeIndex].bindings[bindingIndex].keyCombo = $0
                    viewModel.markChanged()
                }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(width: 180)
            .textFieldStyle(.roundedBorder)

            // Command
            TextField("Command", text: Binding(
                get: { viewModel.modes[modeIndex].bindings[bindingIndex].command },
                set: {
                    viewModel.modes[modeIndex].bindings[bindingIndex].command = $0
                    viewModel.markChanged()
                }
            ))
            .font(.system(.body, design: .monospaced))
            .textFieldStyle(.roundedBorder)

            // Delete
            Button(role: .destructive) {
                viewModel.modes[modeIndex].bindings.remove(at: bindingIndex)
                viewModel.markChanged()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func addBinding() {
        guard selectedModeIndex < viewModel.modes.count else { return }
        viewModel.modes[selectedModeIndex].bindings.append(
            EditableBinding(keyCombo: "", command: "")
        )
        viewModel.markChanged()
    }

    private func addMode() {
        let newName = "mode\(viewModel.modes.count + 1)"
        viewModel.modes.append(EditableMode(name: newName, bindings: []))
        selectedModeIndex = viewModel.modes.count - 1
        viewModel.markChanged()
    }
}
