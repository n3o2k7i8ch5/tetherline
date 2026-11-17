import XCTest
@testable import TetherlineCore

final class PresentationTests: XCTestCase {
    func testFirstLaunchUsesMenuBarWithoutDock() {
        withDefaults { defaults in
            let preferences = PresentationPreferences(defaults: defaults)
            XCTAssertTrue(preferences.showInMenuBar)
            XCTAssertFalse(preferences.showInDock)
        }
    }

    func testAllFourCombinationsSurviveReloadIndependently() {
        withDefaults { defaults in
            for menu in [false, true] {
                for dock in [false, true] {
                    var preferences = PresentationPreferences(defaults: defaults)
                    preferences.showInMenuBar = menu
                    preferences.showInDock = dock
                    preferences.save(to: defaults)
                    let restored = PresentationPreferences(defaults: defaults)
                    XCTAssertEqual(restored.showInMenuBar, menu)
                    XCTAssertEqual(restored.showInDock, dock)
                }
            }
        }
    }

    func testHiddenAppReopensSettingsWithoutForcingEitherIconOn() {
        withDefaults { defaults in
            defaults.set(false, forKey: "showInMenuBar")
            defaults.set(false, forKey: "showInDock")
            let preferences = PresentationPreferences(defaults: defaults)
            XCTAssertEqual(preferences.reopenWindowID, "settings")
            XCTAssertFalse(preferences.showInMenuBar)
            XCTAssertFalse(preferences.showInDock)
            var dockOnly = preferences
            dockOnly.showInDock = true
            XCTAssertEqual(dockOnly.reopenWindowID, "connection")
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "pl.tetherline.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }
}
