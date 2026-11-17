import AppKit
import Foundation
import Security
import ServiceManagement

@MainActor enum SystemIntegration {
    nonisolated static let deployment = Deployment.production
    static let logURL = URL(fileURLWithPath: deployment.engineLogPath)
    static var bundledEngine: String { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/muta").path }
    static var bundledControl: String { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/TetherlineControl").path }

    static var installation: InstallationCheck {
        InstallationCheck(deployment: deployment, bundledEngine: bundledEngine, bundledControl: bundledControl, owner: getuid())
    }

    /// The user switched off Tetherline's background items in System Settings.
    static var approvalRequired: Bool {
        [deployment.enginePlistPath, deployment.controlPlistPath].contains { path in
            FileManager.default.fileExists(atPath: path)
                && SMAppService.statusForLegacyPlist(at: URL(fileURLWithPath: path)) == .requiresApproval
        }
    }

    // MARK: Service actions

    /// Installs or updates the background components when they differ from this
    /// app (the only step that asks for an administrator), then starts tethering.
    static func enable() async throws {
        try validateInstallation()
        let state = try await offloaded { try ServiceState.read(deployment) }
        guard !state.conflict else {
            throw TetherlineError.message(L10n.text("Another tethering service is running. Stop it before enabling Tetherline."))
        }
        let check = installation
        if try await offloaded({ check.state() }) != .current {
            try validateCode(at: URL(fileURLWithPath: bundledControl))
            try await privileged(try await offloaded { try check.installScript() })
            guard try await offloaded({ check.state() }) == .current else {
                throw TetherlineError.message(L10n.text("The background service could not be verified after installation. Try again."))
            }
        }
        if approvalRequired {
            SMAppService.openSystemSettingsLoginItems()
            throw TetherlineError.message(L10n.text("Allow Tetherline to run in the background."))
        }
        try await control(.start)
    }

    static func disable() async throws {
        try await control(.stop)
    }

    /// Quit must leave tethering off. Checks launchd directly rather than a possibly stale UI state.
    static func stopForQuit() async throws {
        let state: ServiceState
        do { state = try await offloaded { try ServiceState.read(deployment) } }
        catch { throw TetherlineError.message(L10n.text("Could not verify that tethering has stopped. Try quitting again.")) }
        if state.loaded { try await control(.stop) }
    }

    static func uninstall() async throws {
        try await privileged(Installer(deployment: deployment).uninstall)
    }

    private static func control(_ action: ControlAction) async throws {
        try await offloaded { try ControlClient.request(action, deployment: deployment) }
    }

    // MARK: Integrity and authorization

    static func validateInstallation() throws {
        guard Bundle.main.bundleURL.path == "/Applications/Tetherline.app" else {
            throw TetherlineError.message(L10n.text("Move Tetherline.app to Applications before enabling the service."))
        }
        try validateCode(at: Bundle.main.bundleURL)
        try validateCode(at: URL(fileURLWithPath: bundledEngine))
    }

    // Integrity checking accepts local ad-hoc signatures. No Apple identity or
    // certificate is required; root executes separate protected copies.
    static func validateCode(at url: URL) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), nil) == errSecSuccess else {
            throw TetherlineError.message(L10n.format("%@ is damaged or has been modified. Rebuild or reinstall Tetherline.", url.lastPathComponent))
        }
    }

    static func privileged(_ shell: String) async throws {
        // The program is passed as one AppleScript string literal, never as shell code.
        let literal = shell.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let result = try await Command.run("/usr/bin/osascript", ["-e", "do shell script \"\(literal)\" with administrator privileges"], timeout: 300)
        guard result.succeeded else {
            throw TetherlineError.message(result.timedOut ? L10n.text("Authorization timed out. Check the service status and try again.") : result.output)
        }
    }

    // MARK: App data

    static func unregister(_ service: SMAppService) async throws {
        guard service.status != .notRegistered && service.status != .notFound else { return }
        try await service.unregister()
    }

    static func removeUserData() throws {
        guard let id = Bundle.main.bundleIdentifier, id == "pl.tetherline.app" else {
            throw TetherlineError.message(L10n.text("Unknown app identifier. Settings were not removed."))
        }
        UserDefaults.standard.removePersistentDomain(forName: id)
        UserDefaults.standard.synchronize()
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        // Remove only this app's exact paths; never sweep shared cache directories.
        for relative in ["Preferences/\(id).plist", "Caches/\(id)", "Saved Application State/\(id).savedState"] {
            let url = library.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }
}
