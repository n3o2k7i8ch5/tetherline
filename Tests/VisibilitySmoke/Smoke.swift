import AppKit

// A separate GUI process and defaults domain; never registers or stops services.
@main enum VisibilitySmoke {
    @MainActor static func main() {
        let application = NSApplication.shared
        let domain = "pl.tetherline.visibility-smoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        let model = AppModel(defaults: defaults, stopForQuit: {})
        let delegate = ApplicationDelegate(model: model)
        application.delegate = delegate
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            for (menu, dock) in [(true, false), (true, true), (false, true), (false, false), (true, false)] {
                model.setMenuBarVisible(menu)
                model.setDockVisible(dock)
                try? await Task.sleep(for: .milliseconds(300))
                precondition(delegate.isMenuBarVisible == menu, "Menu bar visibility")
                precondition(application.activationPolicy() == (dock ? .regular : .accessory), "Dock visibility")
                precondition(model.presentation == PresentationPreferences(defaults: defaults), "Saved preferences")
                precondition(model.settingsErrorMessage == nil, "Settings error")
                for window in application.windows where window.isVisible { window.close() }
                _ = delegate.applicationShouldHandleReopen(application, hasVisibleWindows: false)
                try? await Task.sleep(for: .milliseconds(200))
                let title = !menu && !dock ? L10n.text("Settings") : "Tetherline"
                precondition(application.windows.contains { $0.title == title && $0.isVisible }, "Reopen window")
                precondition(!delegate.applicationShouldTerminateAfterLastWindowClosed(application), "Keep running")
                print("PASS menu=\(menu) dock=\(dock); persisted, reopened \(title)")
            }
            defaults.removePersistentDomain(forName: domain)
            application.terminate(nil)
        }
        withExtendedLifetime(delegate) { application.run() }
    }
}
