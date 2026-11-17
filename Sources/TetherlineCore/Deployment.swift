import Darwin
import Foundation

/// Every root-owned path and launchd label of one installation. Compiled into
/// both the app and the controller; no path or label ever comes from a client.
struct Deployment: Sendable {
    let engineLabel: String
    let controlLabel: String
    let directory: String
    let logDirectory: String
    let appIdentifier: String
    /// Executable name of the engine; also identifies another muta. Letters only:
    /// it is embedded in a process-matching regular expression.
    let engineName: String
    /// muta's fixed status socket, removed on uninstall when no muta is left running.
    let engineSocket: String?
    var launchDaemons = "/Library/LaunchDaemons"

    var enginePath: String { directory + "/" + engineName }
    var controlPath: String { directory + "/TetherlineControl" }
    var socketPath: String { directory + "/control.sock" }
    var enginePlistPath: String { launchDaemons + "/" + engineLabel + ".plist" }
    var controlPlistPath: String { launchDaemons + "/" + controlLabel + ".plist" }
    var engineLogPath: String { logDirectory + "/muta.log" }
    var controlLogPath: String { logDirectory + "/control.log" }
    var engineJob: String { "system/" + engineLabel }
    var controlJob: String { "system/" + controlLabel }

    /// The engine job stays installed. launchd keeps it running while it is loaded;
    /// whether it loads at boot follows the launchd enable/disable override, which
    /// the controller sets on every start and stop. `Standard` avoids background
    /// throttling, as in muta's own service.
    var enginePlist: [String: Any] {
        ["Label": engineLabel, "ProgramArguments": [enginePath, "run"],
         "RunAtLoad": true, "KeepAlive": true, "ProcessType": "Standard",
         "AssociatedBundleIdentifiers": [appIdentifier],
         "StandardOutPath": engineLogPath, "StandardErrorPath": engineLogPath]
    }

    /// The controller is socket-activated: no resident process while idle.
    func controlPlist(owner: uid_t) -> [String: Any] {
        ["Label": controlLabel, "ProgramArguments": [controlPath, String(owner)],
         "Sockets": ["Control": ["SockPathName": socketPath, "SockPathMode": 0o666]],
         "ProcessType": "Interactive", "ThrottleInterval": 1,
         "AssociatedBundleIdentifiers": [appIdentifier],
         "StandardOutPath": controlLogPath, "StandardErrorPath": controlLogPath]
    }

    static let production = Deployment(
        engineLabel: "pl.tetherline.muta", controlLabel: "pl.tetherline.control",
        directory: "/Library/Application Support/Tetherline", logDirectory: "/Library/Logs/Tetherline",
        appIdentifier: "pl.tetherline.app", engineName: "muta", engineSocket: "/var/run/muta.sock")

    /// Isolated twin used by the root probe test; its engine only waits as root.
    static let probe = Deployment(
        engineLabel: "pl.tetherline.probe.engine", controlLabel: "pl.tetherline.probe.control",
        directory: "/Library/Application Support/Tetherline Probe", logDirectory: "/Library/Logs/Tetherline Probe",
        appIdentifier: "pl.tetherline.probe", engineName: "TLProbeEngine", engineSocket: nil)

    /// The deployment a controller binary serves. The probe build never touches production.
    static var current: Deployment {
        #if CONTROL_PROBE
        probe
        #else
        production
        #endif
    }
}
