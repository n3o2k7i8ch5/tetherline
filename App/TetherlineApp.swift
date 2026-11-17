import AppKit
import ServiceManagement
import SwiftUI

#if !UI_PREVIEW
@main
enum Entry {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            Task { @MainActor in
                await diagnose()
                exit(0)
            }
            dispatchMain()
        }
        // launchd may run the login job immediately when the toggle is enabled.
        // Reuse the already-running app instead of creating a second menu item.
        if CommandLine.arguments.contains("--login-item"),
           NSRunningApplication.runningApplications(withBundleIdentifier: "pl.tetherline.app")
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { return }
        let application = NSApplication.shared
        let delegate = ApplicationDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }

    /// Read-only report for support and validation; changes nothing.
    @MainActor static func diagnose() async {
        let observation = await ServiceObservation.read()
        print("bundle: \(Bundle.main.bundlePath)")
        print("installation: \(observation.installation)")
        print("service: loaded=\(observation.service.loaded) pid=\(observation.service.pid.map(String.init) ?? "none") conflict=\(observation.service.conflict)")
        print("approval required: \(observation.approvalRequired)")
        print("login item: \(LoginItem.app.status.rawValue)")
        print("phase: \(ServicePhase(operation: nil, observation: observation).headline)")
        if let error = observation.error { print("error: \(error)") }
        if let status = observation.status { print("muta: \(status.state.rawValue) \(status.interface ?? "")") }
        do {
            try SystemIntegration.validateCode(at: Bundle.main.bundleURL)
            try SystemIntegration.validateCode(at: URL(fileURLWithPath: SystemIntegration.bundledEngine))
            print("code integrity: valid (ad-hoc supported; no Apple certificate required)")
        } catch { print("code integrity: \(error.localizedDescription)") }
    }
}
#endif

@MainActor
enum MenuIcon {
    /// `failed` marks a failed action even when the service itself looks fine.
    static func make(phase: ServicePhase, failed: Bool = false) -> NSImage {
        let name: String
        switch failed ? .failed("") : phase {
        case .failed, .conflict: name = "exclamationmark.triangle"
        case .waiting, .connected: name = "personalhotspot"
        case .checking, .off, .starting, .stopping, .uninstalling, .approvalRequired: name = "personalhotspot.slash"
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
            .withSymbolConfiguration(configuration)!
        let image = NSImage(size: NSSize(width: 26, height: 22), flipped: false) { _ in
            let scale = min(23 / symbol.size.width, 19 / symbol.size.height)
            let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            symbol.draw(in: NSRect(x: (26 - size.width) / 2, y: (22 - size.height) / 2,
                                  width: size.width, height: size.height))
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    var openSettings: (() -> Void)? = nil

    var body: some View {
        let phase = model.phase
        VStack(alignment: .leading, spacing: 20) {
            header(phase)
            connectionCard(phase)

            if !model.busy, let warning = model.observation?.routeWarning {
                notice(title: L10n.text("Check your connection"), message: warning,
                       symbol: "arrow.triangle.branch", tint: .orange)
            }
            if let error = model.operationError {
                notice(title: L10n.text("Action failed"), message: error,
                       symbol: "exclamationmark.triangle.fill", tint: .red)
            }
            if phase == .approvalRequired {
                ActionButton(title: L10n.text("Open System Settings"), systemImage: "gearshape", fillsWidth: true) {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }

            ActionButton(
                title: model.serviceOn ? L10n.text("Turn off") : L10n.text("Enable tethering"),
                systemImage: "power", fillsWidth: true
            ) {
                if model.serviceOn { model.disable() } else { model.enable() }
            }
            .disabled(model.busy || model.observation == nil || (!model.serviceOn && phase == .conflict))

            Divider()

            HStack(spacing: 10) {
                ActionButton(title: L10n.text("View log"), systemImage: "doc.text", tone: .secondary, fillsWidth: true) {
                    model.showLog()
                }
                ActionButton(title: L10n.text("Settings…"), systemImage: "gearshape", tone: .secondary, fillsWidth: true) {
                    if let openSettings { openSettings() }
                    else { ApplicationWindows.shared.showSettings(model: model) }
                }.keyboardShortcut(",", modifiers: .command)
            }
            HStack(spacing: 12) {
                Text("Stops tethering and closes the app.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                ActionButton(title: L10n.text("Quit"), tone: .secondary) {
                    NSApp.terminate(nil)
                }.disabled(model.busy)
            }
        }
        .padding(20).frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Tetherline", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private func header(_ phase: ServicePhase) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "personalhotspot")
                .font(.system(size: 21, weight: .medium))
                .frame(width: 42, height: 42)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("Tetherline").font(.system(size: 18, weight: .semibold))
                Text("Android internet, over USB.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if model.busy || phase == .checking {
                ProgressView().controlSize(.small).accessibilityLabel("Working")
            } else {
                let error = model.hasError
                Label(error ? L10n.text("Error") : (phase.isConnected ? L10n.text("USB") : L10n.text("Offline")),
                      systemImage: error ? "exclamationmark.circle.fill" : (phase.isConnected ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(error ? Color.red : (phase.isConnected ? Color.green : Color.secondary))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.primary.opacity(0.05), in: Capsule())
            }
        }
    }

    private func connectionCard(_ phase: ServicePhase) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbol(for: phase))
                    .font(.system(size: 20))
                    .foregroundStyle(phase.isError ? Color.red : (phase.isConnected ? Color.green : Color.secondary))
                VStack(alignment: .leading, spacing: 4) {
                    Text(phase.headline).font(.system(size: 14, weight: .semibold))
                    if let detail = phase.detail {
                        Text(detail)
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            if case .connected(let status) = phase {
                Divider()
                VStack(spacing: 8) {
                    if let device = status.device { detail("Device", value: device) }
                    if let address = status.address { detail("IP address", value: address) }
                    if let interface = status.interface { detail("Interface", value: interface) }
                    detail("Packets", value: "↓ \(status.packetsIn.map(String.init) ?? "—")   ↑ \(status.packetsOut.map(String.init) ?? "—")")
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(phase.isError ? Color.red.opacity(0.07) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(phase.isError ? Color.red.opacity(0.16) : Color.primary.opacity(0.06)))
    }

    private func symbol(for phase: ServicePhase) -> String {
        switch phase {
        case .failed, .conflict: "exclamationmark.triangle.fill"
        case .connected: "checkmark.circle.fill"
        case .approvalRequired: "lock.circle"
        case .starting, .stopping, .uninstalling, .checking: "hourglass"
        case .off, .waiting: "cable.connector"
        }
    }

    private func detail(_ title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled).monospacedDigit()
        }.font(.system(size: 11))
    }

    private func notice(title: String, message: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint).padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}
