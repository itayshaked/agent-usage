import Foundation
import SQLite3

/// Reads Cursor's own session token from the IDE's local storage so the app can
/// authenticate without a manual paste. The IDE refreshes this token on its own,
/// so re-reading it before each fetch keeps us from ever expiring.
enum LocalTokenReader {
    private static var dbPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
            .path
    }

    /// Full `sub::jwt` cookie value, or nil if the Cursor app isn't logged in.
    static func cookieToken() -> String? {
        guard let jwt = accessToken(), let sub = subFromJWT(jwt) else { return nil }
        return "\(sub)::\(jwt)"
    }

    static var isAvailable: Bool { cookieToken() != nil }

    private static func accessToken() -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken' LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            let value = String(cString: c).trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespacesAndNewlines))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private static func subFromJWT(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2, let data = base64urlDecode(String(parts[1])),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = obj["sub"] as? String else { return nil }
        return sub
    }

    private static func base64urlDecode(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }
}
