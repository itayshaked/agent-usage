import Foundation
import SQLite3

/// Reads Cursor's own session token from the IDE's local storage so the app can
/// authenticate without a manual paste. The IDE refreshes this token on its own,
/// so re-reading it before each fetch keeps us from ever expiring.
///
/// The stored token has taken three shapes, all handled here:
/// - a JWT (`eyJ…`) whose `sub` claim names the user (before 3.27.12);
/// - an opaque `curs…` token, with the user in `cachedScopedProfile` (3.27.12+);
/// - either of those sealed by safeStorage, `cursor-safe-storage:v1:…` (3.27.22+).
enum LocalTokenReader {
    private static var dbPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
            .path
    }

    /// `userId::token` cookie value (or the bare token if the user can't be
    /// determined), or nil if the Cursor app isn't logged in.
    static func cookieToken() -> String? {
        guard let token = accessToken() else { return nil }
        guard let userID = userID(for: token) else { return token }
        return "\(userID)::\(token)"
    }

    static var isAvailable: Bool { cookieToken() != nil }

    private static func accessToken() -> String? {
        guard let raw = readValue(key: "cursorAuth/accessToken") else { return nil }
        let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespacesAndNewlines))
        if value.hasPrefix(CursorSafeStorage.prefix) {
            return CursorSafeStorage.unseal(String(value.dropFirst(CursorSafeStorage.prefix.count)))
        }
        return value.isEmpty ? nil : value
    }

    private static func userID(for token: String) -> String? {
        if let sub = subFromJWT(token) { return sub }

        // Opaque tokens carry no claims; the IDE caches the identity separately
        // as {"authId":"<issuer>|user_…", …}.
        guard let raw = readValue(key: "cursorAuth/cachedScopedProfile") else { return nil }
        var json = try? JSONSerialization.jsonObject(with: Data(raw.utf8), options: .fragmentsAllowed)
        // Tolerate the profile being stored as a JSON-encoded string.
        if let nested = json as? String {
            json = try? JSONSerialization.jsonObject(with: Data(nested.utf8))
        }
        return JSON.string(json, keys: ["authId", "sub"])
    }

    private static func readValue(key: String) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key=? LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, key, -1, transient)

        if sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            let value = String(cString: c)
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
