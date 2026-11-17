import Foundation
import ServiceManagement

let service = SMAppService.daemon(plistName: "pl.tetherline.signing-probe.plist")
let action = CommandLine.arguments.dropFirst().first ?? "status"
do {
    switch action {
    case "register":
        do { try service.register() }
        catch {
            guard service.status == .requiresApproval else { throw error }
            print("Registration is recorded; macOS requires administrator approval.")
        }
    case "unregister":
        if service.status == .enabled || service.status == .requiresApproval { try service.unregister() }
    case "settings": SMAppService.openSystemSettingsLoginItems()
    default: break
    }
    print("SMAppService status: \(service.status.rawValue) (0=notRegistered, 1=enabled, 2=requiresApproval, 3=notFound)")
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}

