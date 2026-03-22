import Common
import SwiftUI

struct GeneralSettingsTab: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Start at login", isOn: $viewModel.startAtLogin)
                Toggle("Auto-reload config on save", isOn: $viewModel.autoReloadConfig)
            }

            Section("Layout") {
                Picker("Default layout", selection: $viewModel.defaultLayout) {
                    Text("Tiles").tag("tiles")
                    Text("Accordion").tag("accordion")
                }
                .pickerStyle(.segmented)

                Picker("Default orientation", selection: $viewModel.defaultOrientation) {
                    Text("Auto").tag("auto")
                    Text("Horizontal").tag("horizontal")
                    Text("Vertical").tag("vertical")
                }
                .pickerStyle(.segmented)

                Stepper("Accordion padding: \(viewModel.accordionPadding)px",
                        value: $viewModel.accordionPadding, in: 0...200, step: 5)
            }

            Section("Normalization") {
                Toggle("Flatten containers", isOn: $viewModel.enableNormalizationFlatten)
                Toggle("Opposite orientation for nested containers",
                       isOn: $viewModel.enableNormalizationOpposite)
            }

            Section("Behavior") {
                Toggle("Automatically unhide macOS hidden apps",
                       isOn: $viewModel.automaticallyUnhideMacosHiddenApps)
            }

            Section("Keyboard") {
                Picker("Key mapping preset", selection: $viewModel.keyMappingPreset) {
                    Text("QWERTY").tag("qwerty")
                    Text("Dvorak").tag("dvorak")
                    Text("Colemak").tag("colemak")
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: viewModel.startAtLogin) { _ in viewModel.markChanged() }
        .onChange(of: viewModel.autoReloadConfig) { _ in viewModel.markChanged() }
        .onChange(of: viewModel.automaticallyUnhideMacosHiddenApps) { _ in viewModel.markChanged() }
        .onChange(of: viewModel.enableNormalizationFlatten) { _ in viewModel.markChanged() }
        .onChange(of: viewModel.enableNormalizationOpposite) { _ in viewModel.markChanged() }
        .onChange(of: viewModel.defaultLayout) { _ in viewModel.markChanged() }
        .onChange(of: viewModel.defaultOrientation) { _ in viewModel.markChanged() }
        .onChange(of: viewModel.accordionPadding) { _ in viewModel.markChanged() }
        .onChange(of: viewModel.keyMappingPreset) { _ in viewModel.markChanged() }
    }
}
