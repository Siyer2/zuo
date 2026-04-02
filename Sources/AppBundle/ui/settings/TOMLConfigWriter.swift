import Common
import Foundation
import TOMLKit

@MainActor
enum TOMLConfigWriter {
    /// Read the current config file as a parsed TOMLTable and its URL
    static func readCurrentConfig() -> (table: TOMLTable, url: URL)? {
        let url: URL
        switch findCustomConfigUrl() {
            case .file(let foundUrl):
                url = foundUrl
            case .noCustomConfigExists:
                // Copy default config to ~/.zuo.toml first
                let fallback = FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName)
                _ = try? FileManager.default.copyItem(atPath: defaultConfigUrl.path, toPath: fallback.path)
                url = fallback
            case .ambiguousConfigError:
                return nil
        }

        guard let contents = try? String(contentsOf: url, encoding: .utf8),
              let table = try? TOMLTable(string: contents) else {
            return nil
        }
        return (table, url)
    }

    /// Write a TOMLTable back to a config file URL
    static func writeConfig(_ table: TOMLTable, to url: URL) throws {
        let tomlString = table.tomlString
        try tomlString.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Get or create a sub-table at a key path, creating intermediate tables as needed
    static func getOrCreateTable(_ table: TOMLTable, key: String) -> TOMLTable {
        if let existing = table[key]?.table {
            return existing
        }
        let newTable = TOMLTable()
        table[key] = newTable
        return newTable
    }
}
