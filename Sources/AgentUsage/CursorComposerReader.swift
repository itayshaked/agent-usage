import Foundation
import SQLite3

/// Reads the names Cursor already gave its conversations.
///
/// Every billed usage event carries a `conversationId`, and Cursor's own
/// `composerHeaders` table stores that id alongside the title it generated for
/// the chat ("Zone events coordinate format"). Joining the two is what lets the
/// session list label itself with no typing.
enum CursorComposerReader {
    struct Composer {
        let name: String?
        let workspaceID: String?
        let isSubagent: Bool
        let subagentTypeName: String?
    }

    private static var dbPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
            .path
    }

    /// Composer headers keyed by composer id (== the billing `conversationId`).
    /// Returns empty if Cursor isn't installed or the table has moved — the
    /// session list still works, it just falls back to shortened ids.
    static func composers() -> [String: Composer] {
        var db: OpaquePointer?
        // Cursor holds this database open, so read-only + shared cache avoids
        // fighting it for the lock.
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = """
            SELECT composerId, workspaceId, isSubagent, subagentTypeName, value
            FROM composerHeaders;
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }

        var result: [String: Composer] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idText = sqlite3_column_text(stmt, 0) else { continue }
            let id = String(cString: idText)

            let workspace = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let isSubagent = sqlite3_column_int(stmt, 2) != 0
            let subagentType = sqlite3_column_text(stmt, 3).map { String(cString: $0) }

            // The name lives inside the row's JSON blob, not its own column.
            var name: String?
            if let valueText = sqlite3_column_text(stmt, 4) {
                let json = try? JSONSerialization.jsonObject(with: Data(String(cString: valueText).utf8))
                name = JSON.string(json, keys: ["name"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            result[id] = Composer(name: (name?.isEmpty ?? true) ? nil : name,
                                  workspaceID: workspace,
                                  isSubagent: isSubagent,
                                  subagentTypeName: subagentType)
        }
        return result
    }
}
