import Foundation

/// Everything one poll learned. Published as a whole, so the UI never mixes polls.
struct ServiceObservation: Equatable, Sendable {
    var installation: InstallationState = .missing
    /// macOS disallowed Tetherline's background items (System Settings → Login Items).
    var approvalRequired = false
    var service = ServiceState()
    var status: MutaStatus?
    /// The service state, or the running engine's status, could not be read.
    var error: String?
    var routeWarning: String?
}

/// A user action in progress. While a service action runs, it alone decides what
/// the UI shows: starting and stopping pass through states that only look like
/// failures (a job unloading, an engine not answering yet).
enum ServiceOperation: Equatable, Sendable {
    case enabling, disabling, quitting, uninstalling, changingLoginItem

    var affectsService: Bool { self != .changingLoginItem }
}

/// The single state the UI renders: icon, headline, detail and primary action.
enum ServicePhase: Equatable, Sendable {
    case checking
    case off(needsAdministrator: Bool)
    case starting, stopping, uninstalling
    case approvalRequired
    case conflict
    case waiting
    case connected(MutaStatus)
    case failed(String)

    init(operation: ServiceOperation?, observation: ServiceObservation?) {
        switch operation {
        case .enabling: self = .starting; return
        case .disabling, .quitting: self = .stopping; return
        case .uninstalling: self = .uninstalling; return
        case .changingLoginItem, nil: break
        }
        guard let o = observation else { self = .checking; return }
        if o.service.conflict {
            self = .conflict
        } else if o.service.running {
            if let status = o.status {
                self = status.state == .connected ? .connected(status) : .waiting
            } else {
                self = .failed(o.error ?? L10n.text("Unable to read the connection status. Check the log."))
            }
        } else if let error = o.error {
            self = .failed(error)
        } else if o.approvalRequired {
            self = .approvalRequired
        } else if o.service.loaded {
            self = .failed(L10n.text("The service is on but not running. Check the log, then turn tethering off and on."))
        } else {
            self = .off(needsAdministrator: o.installation != .current)
        }
    }

    var headline: String {
        switch self {
        case .checking: L10n.text("Checking…")
        case .off: L10n.text("Tethering is off")
        case .starting: L10n.text("Turning on…")
        case .stopping: L10n.text("Turning off…")
        case .uninstalling: L10n.text("Uninstalling…")
        case .approvalRequired: L10n.text("Approval needed")
        case .conflict: L10n.text("Another tethering service is running")
        case .waiting: L10n.text("Waiting for your phone")
        case .connected: L10n.text("Connected over USB")
        case .failed: L10n.text("Service unavailable")
        }
    }

    var detail: String? {
        switch self {
        case .off(let needsAdministrator):
            needsAdministrator
                ? L10n.text("Enable tethering to connect your phone. macOS will ask for administrator approval to install the background service.")
                : L10n.text("Enable tethering to connect your phone.")
        case .approvalRequired: L10n.text("Allow Tetherline to run in the background.")
        case .conflict: L10n.text("Stop the other tethering service before enabling Tetherline.")
        case .waiting: L10n.text("Connect your phone and turn on USB tethering.")
        case .failed(let message): message
        case .checking, .starting, .stopping, .uninstalling, .connected: nil
        }
    }

    var isError: Bool {
        switch self {
        case .failed, .conflict: true
        default: false
        }
    }

    var isConnected: Bool {
        if case .connected = self { true } else { false }
    }
}
