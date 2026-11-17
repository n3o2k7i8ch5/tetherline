import CoreWLAN
import Foundation

extension ServiceObservation {
    /// One complete reading of the system, without root: installation, launchd,
    /// processes and, when the engine runs, its own status. Nothing is published
    /// until the whole reading is done.
    @MainActor static func read() async -> Self {
        var observation = Self()
        observation.approvalRequired = SystemIntegration.approvalRequired
        let check = SystemIntegration.installation
        do {
            (observation.installation, observation.service) = try await offloaded {
                (check.state(), try ServiceState.read(check.deployment))
            }
        } catch {
            observation.error = error.localizedDescription
            return observation
        }
        guard observation.service.running else { return observation }
        do {
            // The installed engine answers for the engine that runs, whatever this bundle contains.
            let result = try await Command.run(check.deployment.enginePath, ["status"], timeout: 2)
            guard result.succeeded else {
                throw TetherlineError.message(L10n.text("Unable to read the connection status. Check the log."))
            }
            let status = try MutaStatus(output: result.output)
            observation.status = status
            if status.state == .connected {
                let route = try? await Command.run("/sbin/route", ["-n", "get", "default"], timeout: 2)
                let primary = route.flatMap { $0.succeeded ? RouteStatus.interface(from: $0.output) : nil }
                let wifi = Set(CWWiFiClient.shared().interfaceNames() ?? [])
                observation.routeWarning = RouteStatus.warning(tether: status.interface, primary: primary, wifiInterfaces: wifi)
            }
        } catch {
            observation.error = error.localizedDescription
        }
        return observation
    }
}
