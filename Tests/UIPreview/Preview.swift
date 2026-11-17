import AppKit
import SwiftUI

// Renders the actual SwiftUI views. "live" reads system state; no state changes services.
@main enum Preview {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let arguments = CommandLine.arguments
        let output = arguments[1]
        let state = arguments[2]
        let dark = arguments[3] == "dark"
        let model = AppModel()
        let running = ServiceState(loaded: true, pid: 42)
        switch state {
        case "off": model.observation = ServiceObservation(installation: .current)
        case "setup": model.observation = ServiceObservation(installation: .outdated)
        case "connected":
            model.observation = ServiceObservation(installation: .current, service: running, status: try MutaStatus(
                output: "state connected\ndevice SAMSUNG Galaxy S23+\ninterface utun5\naddress 10.221.188.173\nin 43597\nout 40568"))
        case "route":
            model.observation = ServiceObservation(installation: .current, service: running, status: try MutaStatus(
                output: "state connected\ninterface utun5\naddress 10.221.188.173\nin 1\nout 2"),
                routeWarning: L10n.text("Connected, but the default IPv4 route uses Wi-Fi."))
        case "waiting": model.observation = ServiceObservation(installation: .current, service: running, status: try MutaStatus(output: "state waiting"))
        case "failed": model.observation = ServiceObservation(installation: .current, service: ServiceState(loaded: true))
        case "conflict": model.observation = ServiceObservation(installation: .current, service: ServiceState(conflict: true))
        case "approval", "settings-approval":
            model.observation = ServiceObservation(installation: .current, approvalRequired: true)
            if state == "settings-approval" { model.loginStatus = .requiresApproval }
        case "operation-failed":
            model.observation = ServiceObservation(installation: .current)
            model.operationError = "The service did not start. Check the log and background permission in System Settings."
        case "starting":
            model.observation = ServiceObservation(installation: .current)
            model.operation = .enabling
        case "stopping": // The reading from before Turn off: still loaded.
            model.observation = ServiceObservation(installation: .current, service: running, status: try MutaStatus(output: "state waiting"))
            model.operation = .disabling
        case "live":
            await model.refresh()
            print("Live observation: \(String(describing: model.observation))")
        default: model.observation = ServiceObservation(installation: .current)
        }

        let content = state == "uninstall-confirmation" ? AnyView(SettingsView(model: model).uninstallConfirmation)
            : state.hasPrefix("settings") ? AnyView(SettingsView(model: model)) : AnyView(MenuContent(model: model))
        let root = content
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.controlActiveState, arguments.contains("--inactive") ? .inactive : .key)
        let view = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = view
        view.setFrameSize(view.fittingSize)
        window.setContentSize(view.frame.size)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw TetherlineError.message("Cannot create preview bitmap")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw TetherlineError.message("Cannot encode preview")
        }
        try png.write(to: URL(fileURLWithPath: output))
        print("\(Bundle.main.preferredLocalizations): \(model.phase.headline); \(Int(view.frame.width)) × \(Int(view.frame.height))")
    }
}
