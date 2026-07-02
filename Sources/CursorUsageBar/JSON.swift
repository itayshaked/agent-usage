import Foundation

/// Defensive helpers for pulling values out of unofficial, drift-prone JSON.
/// Keys are searched recursively so nested wrappers don't break extraction.
enum JSON {
    static func find(_ json: Any?, keys: [String]) -> Any? {
        guard let json else { return nil }
        if let dict = json as? [String: Any] {
            for key in keys {
                if let value = dict[key], !(value is NSNull) { return value }
            }
            for value in dict.values {
                if let found = find(value, keys: keys) { return found }
            }
        } else if let array = json as? [Any] {
            for value in array {
                if let found = find(value, keys: keys) { return found }
            }
        }
        return nil
    }

    static func string(_ json: Any?, keys: [String]) -> String? {
        find(json, keys: keys) as? String
    }

    static func int(_ json: Any?, keys: [String]) -> Int? {
        switch find(json, keys: keys) {
        case let n as Int: return n
        case let n as Double: return Int(n)
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }

    static func double(_ json: Any?, keys: [String]) -> Double? {
        switch find(json, keys: keys) {
        case let n as Double: return n
        case let n as Int: return Double(n)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    static func date(_ json: Any?, keys: [String]) -> Date? {
        parseDate(find(json, keys: keys))
    }

    static func parseDate(_ value: Any?) -> Date? {
        if let s = value as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            iso.formatOptions = [.withInternetDateTime]
            if let d = iso.date(from: s) { return d }
            if let ms = Double(s) { return dateFromEpoch(ms) }
        }
        if let n = value as? NSNumber { return dateFromEpoch(n.doubleValue) }
        return nil
    }

    private static func dateFromEpoch(_ value: Double) -> Date {
        // Heuristic: values that big are milliseconds.
        let seconds = value > 1_000_000_000_000 ? value / 1000.0 : value
        return Date(timeIntervalSince1970: seconds)
    }

    /// Collects every dictionary in the tree that satisfies `predicate`.
    static func collectDicts(_ json: Any?, where predicate: ([String: Any]) -> Bool) -> [[String: Any]] {
        var result: [[String: Any]] = []
        func walk(_ node: Any?) {
            if let dict = node as? [String: Any] {
                // A matched dict is treated as a leaf record so we don't also
                // sum any nested breakdown it may contain.
                if predicate(dict) {
                    result.append(dict)
                    return
                }
                for value in dict.values { walk(value) }
            } else if let array = node as? [Any] {
                for value in array { walk(value) }
            }
        }
        walk(json)
        return result
    }
}
