import AppKit
import ServiceManagement

@MainActor struct LoginItem {
    static let app = LoginItem(label: "pl.tetherline.app",
                              executable: "/bin/sh",
                              arguments: ["-c", "if ! /usr/bin/pgrep -u \(getuid()) -x Tetherline >/dev/null; then exec /usr/bin/open -gj /Applications/Tetherline.app --args --login-item; fi"])
    // The login job is a short-lived launcher. Launch Services owns the GUI, so
    // booting out the login job cannot terminate the app while it removes its plist.
    let label: String
    let executable: String
    let arguments: [String]
    var url: URL { FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(label).plist") }
    var job: String { "gui/\(getuid())/\(label)" }

    var status: SMAppService.Status {
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Allow disabling a login registration made by an older build.
            return label == Self.app.label ? SMAppService.mainApp.status : .notRegistered
        }
        return SMAppService.statusForLegacyPlist(at: url) == .requiresApproval ? .requiresApproval : .enabled
    }

    func setEnabled(_ enabled: Bool) async throws {
        if label == Self.app.label {
            if enabled { try SystemIntegration.validateInstallation() }
            try await SystemIntegration.unregister(SMAppService.mainApp)
        }
        let loaded = try await Command.run("/bin/launchctl", ["print", job])
        if loaded.status == 0 { try await run(["bootout", job]) }
        if enabled {
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executable] + arguments,
                "RunAtLoad": true, "LimitLoadToSessionType": "Aqua",
                "AssociatedBundleIdentifiers": [label]
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try await run(["enable", job])
            try await run(["bootstrap", "gui/\(getuid())", url.path])
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func run(_ arguments: [String]) async throws {
        let result = try await Command.run("/bin/launchctl", arguments)
        guard result.status == 0, !result.timedOut else {
            throw TetherlineError.message(L10n.text("The login item could not be changed. Check background permission in System Settings and try again.") + "\n" + result.output)
        }
    }
}
