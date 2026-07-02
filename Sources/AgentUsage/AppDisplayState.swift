import Foundation

/// Which provider(s) to show in the compact menu bar label. The dropdown
/// always shows both sections regardless of this setting.
enum DisplayPreference: String, CaseIterable {
    case both
    case cursorOnly
    case claudeOnly

    var label: String {
        switch self {
        case .both: return "Both"
        case .cursorOnly: return "Cursor only"
        case .claudeOnly: return "Claude only"
        }
    }
}

@MainActor
final class AppDisplayState: ObservableObject {
    @Published var preference: DisplayPreference
    private let key = "displayPreference"

    init() {
        preference = DisplayPreference(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .both
    }

    func setPreference(_ newValue: DisplayPreference) {
        preference = newValue
        UserDefaults.standard.set(newValue.rawValue, forKey: key)
    }
}
