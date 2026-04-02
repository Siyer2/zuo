import Common
import Foundation
import TOMLKit

@MainActor
public final class SettingsViewModel: ObservableObject {
    public static let shared = SettingsViewModel()

    // MARK: - General Settings
    @Published var startAtLogin: Bool = false
    @Published var autoReloadConfig: Bool = false
    @Published var automaticallyUnhideMacosHiddenApps: Bool = false
    @Published var enableNormalizationFlatten: Bool = true
    @Published var enableNormalizationOpposite: Bool = true
    @Published var defaultLayout: String = "tiles"
    @Published var defaultOrientation: String = "auto"
    @Published var accordionPadding: Int = 30
    @Published var keyMappingPreset: String = "qwerty"

    // MARK: - Gaps
    @Published var innerHorizontal: Int = 0
    @Published var innerVertical: Int = 0
    @Published var outerLeft: Int = 0
    @Published var outerRight: Int = 0
    @Published var outerTop: Int = 0
    @Published var outerBottom: Int = 0
    @Published var hasPerMonitorGaps: Bool = false

    // MARK: - Keybindings
    @Published var modes: [EditableMode] = []

    // MARK: - Workspaces
    @Published var persistentWorkspaces: [String] = []

    // MARK: - State
    @Published public var isSettingsOpen: Bool = false
    @Published var hasUnsavedChanges: Bool = false
    @Published var showCommentWarning: Bool = false

    private var tomlTable: TOMLTable?
    private(set) var configUrl: URL?
    private var isFirstSave: Bool = true

    private init() {}

    // MARK: - Load

    func load() {
        guard let (table, url) = TOMLConfigWriter.readCurrentConfig() else { return }
        tomlTable = table
        configUrl = url

        // General
        startAtLogin = table["start-at-login"]?.bool ?? false
        autoReloadConfig = table["auto-reload-config"]?.bool ?? false
        automaticallyUnhideMacosHiddenApps = table["automatically-unhide-macos-hidden-apps"]?.bool ?? false
        enableNormalizationFlatten = table["enable-normalization-flatten-containers"]?.bool ?? true
        enableNormalizationOpposite = table["enable-normalization-opposite-orientation-for-nested-containers"]?.bool ?? true
        defaultLayout = table["default-root-container-layout"]?.string ?? "tiles"
        defaultOrientation = table["default-root-container-orientation"]?.string ?? "auto"
        accordionPadding = table["accordion-padding"]?.int ?? 30

        // Key mapping
        if let keyMappingTable = table["key-mapping"]?.table {
            keyMappingPreset = keyMappingTable["preset"]?.string ?? "qwerty"
        } else {
            keyMappingPreset = "qwerty"
        }

        // Gaps
        loadGaps(from: table)

        // Keybindings
        loadModes(from: table)

        // Workspaces
        if let workspacesArray = table["persistent-workspaces"]?.array {
            persistentWorkspaces = workspacesArray.compactMap { $0.string }
        } else {
            persistentWorkspaces = []
        }

        hasUnsavedChanges = false
        isFirstSave = true
    }

    private func loadGaps(from table: TOMLTable) {
        hasPerMonitorGaps = false
        guard let gapsTable = table["gaps"]?.table else {
            innerHorizontal = 0; innerVertical = 0
            outerLeft = 0; outerRight = 0; outerTop = 0; outerBottom = 0
            return
        }

        func loadGapValue(_ table: TOMLTable, _ key: String) -> Int {
            if let value = table[key] {
                if let intVal = value.int {
                    return intVal
                } else if value.array != nil {
                    hasPerMonitorGaps = true
                    return 0
                }
            }
            return 0
        }

        if let innerTable = gapsTable["inner"]?.table {
            innerHorizontal = loadGapValue(innerTable, "horizontal")
            innerVertical = loadGapValue(innerTable, "vertical")
        } else {
            // Handle flat dot-notation: inner.horizontal etc
            innerHorizontal = gapsTable["inner.horizontal"]?.int ?? 0
            innerVertical = gapsTable["inner.vertical"]?.int ?? 0
        }

        if let outerTable = gapsTable["outer"]?.table {
            outerLeft = loadGapValue(outerTable, "left")
            outerRight = loadGapValue(outerTable, "right")
            outerTop = loadGapValue(outerTable, "top")
            outerBottom = loadGapValue(outerTable, "bottom")
        } else {
            outerLeft = gapsTable["outer.left"]?.int ?? 0
            outerRight = gapsTable["outer.right"]?.int ?? 0
            outerTop = gapsTable["outer.top"]?.int ?? 0
            outerBottom = gapsTable["outer.bottom"]?.int ?? 0
        }
    }

    private func loadModes(from table: TOMLTable) {
        modes = []
        guard let modesTable = table["mode"]?.table else { return }
        for (modeName, modeValue) in modesTable {
            guard let modeTable = modeValue.table,
                  let bindingTable = modeTable["binding"]?.table else { continue }
            var bindings: [EditableBinding] = []
            for (keyCombo, commandValue) in bindingTable {
                let command: String
                if let str = commandValue.string {
                    command = str
                } else if let arr = commandValue.array {
                    command = "[" + arr.compactMap({ $0.string }).map({ "'\($0)'" }).joined(separator: ", ") + "]"
                } else {
                    command = String(describing: commandValue)
                }
                bindings.append(EditableBinding(keyCombo: keyCombo, command: command))
            }
            bindings.sort { $0.keyCombo < $1.keyCombo }
            modes.append(EditableMode(name: modeName, bindings: bindings))
        }
        modes.sort { lhs, rhs in
            if lhs.name == mainModeId { return true }
            if rhs.name == mainModeId { return false }
            return lhs.name < rhs.name
        }
    }

    // MARK: - Save

    func save() {
        guard let tomlTable, let configUrl else { return }

        // General
        tomlTable["config-version"] = 2
        tomlTable["start-at-login"] = startAtLogin
        tomlTable["auto-reload-config"] = autoReloadConfig
        tomlTable["automatically-unhide-macos-hidden-apps"] = automaticallyUnhideMacosHiddenApps
        tomlTable["enable-normalization-flatten-containers"] = enableNormalizationFlatten
        tomlTable["enable-normalization-opposite-orientation-for-nested-containers"] = enableNormalizationOpposite
        tomlTable["default-root-container-layout"] = defaultLayout
        tomlTable["default-root-container-orientation"] = defaultOrientation
        tomlTable["accordion-padding"] = accordionPadding

        // Key mapping
        let keyMappingTable = TOMLConfigWriter.getOrCreateTable(tomlTable, key: "key-mapping")
        keyMappingTable["preset"] = keyMappingPreset

        // Gaps (only write if not per-monitor)
        if !hasPerMonitorGaps {
            saveGaps(to: tomlTable)
        }

        // Keybindings
        saveModes(to: tomlTable)

        // Workspaces
        let workspacesArray = TOMLArray(persistentWorkspaces)
        tomlTable["persistent-workspaces"] = workspacesArray

        do {
            try TOMLConfigWriter.writeConfig(tomlTable, to: configUrl)
            hasUnsavedChanges = false

            // Trigger config reload
            Task {
                _ = try? await reloadConfig()
            }
        } catch {
            // Config write failed — user will see stale state
        }
    }

    private func saveGaps(to table: TOMLTable) {
        let gapsTable = TOMLConfigWriter.getOrCreateTable(table, key: "gaps")

        let innerTable = TOMLConfigWriter.getOrCreateTable(gapsTable, key: "inner")
        innerTable["horizontal"] = innerHorizontal
        innerTable["vertical"] = innerVertical

        let outerTable = TOMLConfigWriter.getOrCreateTable(gapsTable, key: "outer")
        outerTable["left"] = outerLeft
        outerTable["right"] = outerRight
        outerTable["top"] = outerTop
        outerTable["bottom"] = outerBottom
    }

    private func saveModes(to table: TOMLTable) {
        let modesTable = TOMLConfigWriter.getOrCreateTable(table, key: "mode")

        for mode in modes {
            let modeTable = TOMLConfigWriter.getOrCreateTable(modesTable, key: mode.name)
            let bindingTable = TOMLTable()
            for binding in mode.bindings {
                guard !binding.keyCombo.isEmpty, !binding.command.isEmpty else { continue }
                // Handle array commands like ['cmd1', 'cmd2']
                if binding.command.hasPrefix("[") && binding.command.hasSuffix("]") {
                    let inner = String(binding.command.dropFirst().dropLast())
                    let commands = inner.split(separator: ",").map {
                        String($0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "'")))
                    }
                    bindingTable[binding.keyCombo] = TOMLArray(commands)
                } else {
                    bindingTable[binding.keyCombo] = binding.command
                }
            }
            modeTable["binding"] = bindingTable
        }
    }

    // MARK: - Revert

    func revert() {
        load()
    }

    // MARK: - Change tracking

    func markChanged() {
        hasUnsavedChanges = true
    }
}

// MARK: - Editable Models

struct EditableBinding: Identifiable {
    let id = UUID()
    var keyCombo: String
    var command: String
}

struct EditableMode: Identifiable {
    let id = UUID()
    var name: String
    var bindings: [EditableBinding]
}
