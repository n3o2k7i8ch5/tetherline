import Foundation

struct MutaStatus: Equatable, Sendable {
    enum State: String, Sendable { case connected, waiting }
    let state: State
    let device: String?
    let interface: String?
    let address: String?
    let packetsIn: UInt64?
    let packetsOut: UInt64?

    init(output: String) throws {
        var fields: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { continue }
            fields[String(parts[0])] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        guard let raw = fields["state"], let state = State(rawValue: raw) else {
            throw TetherlineError.message(L10n.text("Unknown muta status format. Check that the engine version is compatible."))
        }
        self.state = state
        func value(_ key: String) -> String? {
            guard let v = fields[key], v != "-", !v.isEmpty else { return nil }
            return v
        }
        device = value("device")
        interface = value("interface")
        address = value("address")
        packetsIn = value("in").flatMap(UInt64.init)
        packetsOut = value("out").flatMap(UInt64.init)
        if state == .connected && (interface == nil || address == nil) {
            throw TetherlineError.message(L10n.text("The connection status is incomplete."))
        }
    }
}

enum RouteStatus {
    static func interface(from output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2 && pair[0].trimmingCharacters(in: .whitespaces) == "interface" {
                let value = pair[1].trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    static func warning(tether: String?, primary: String?, wifiInterfaces: Set<String>) -> String? {
        guard let tether else { return nil }
        guard let primary else { return L10n.text("Connected, but the default IPv4 route could not be determined.") }
        guard tether != primary else { return nil }
        if wifiInterfaces.contains(primary) { return L10n.text("Connected, but the default IPv4 route uses Wi-Fi.") }
        return L10n.format("Connected, but the default IPv4 route uses %@ (such as a VPN or Ethernet).", primary)
    }
}
