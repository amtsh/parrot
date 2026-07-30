import Foundation

/// Persists the last model picked from the menu bar so it's the default on
/// the next launch. A `--model` flag always overrides this without writing
/// to it.
enum ModelPreference {
    private static let key = "parrot.selectedModelID"

    static var selectedModelID: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
