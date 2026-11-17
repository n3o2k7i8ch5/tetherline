import Foundation

struct PresentationPreferences: Equatable {
    var showInMenuBar: Bool
    var showInDock: Bool

    init(defaults: UserDefaults) {
        showInMenuBar = defaults.object(forKey: "showInMenuBar") as? Bool ?? true
        showInDock = defaults.object(forKey: "showInDock") as? Bool ?? false
    }

    func save(to defaults: UserDefaults) {
        defaults.set(showInMenuBar, forKey: "showInMenuBar")
        defaults.set(showInDock, forKey: "showInDock")
    }

    var reopenWindowID: String { showInMenuBar || showInDock ? "connection" : "settings" }
}
