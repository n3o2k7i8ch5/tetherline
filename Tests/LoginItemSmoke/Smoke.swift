import Foundation

@main enum LoginItemSmoke {
    @MainActor static func main() async throws {
        let item = LoginItem(label: "pl.tetherline.login-probe", executable: "/usr/bin/true", arguments: [])
        guard !FileManager.default.fileExists(atPath: item.url.path) else {
            throw TetherlineError.message("A previous login probe exists; inspect it before rerunning.")
        }
        do {
            try await item.setEnabled(true)
            let state = try await Command.run("/bin/launchctl", ["print", item.job])
            precondition(state.status == 0 && state.output.contains("/usr/bin/true"), "Login job loads")
            precondition(FileManager.default.fileExists(atPath: item.url.path), "Login plist persists")
            print("PASS user login item installed and loaded without an Apple certificate")
            try await item.setEnabled(false)
            let removed = try await Command.run("/bin/launchctl", ["print", item.job])
            precondition(removed.status != 0 && !FileManager.default.fileExists(atPath: item.url.path), "Login item removed")
            try await item.setEnabled(false)
            print("PASS login item removed; repeated removal is safe")
        } catch {
            try? await item.setEnabled(false)
            throw error
        }
    }
}
