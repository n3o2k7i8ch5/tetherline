import Darwin
import Foundation

/// Writes the root test for the isolated probe deployment and, optionally, the
/// production installation that runs only after every probe check passed.
///
///     generate <build dir> <output> [<Tetherline.app>]
@main enum Generate {
    static func main() throws {
        let arguments = CommandLine.arguments
        let base = arguments[1]
        let output = arguments[2]
        let owner = getuid()
        let d = Deployment.probe
        let q = Installer.quote
        let check = InstallationCheck(deployment: d, bundledEngine: base + "/engine", bundledControl: base + "/controller", owner: owner)
        let install = try check.installScript()
        let corrupt = try Installer(deployment: d).install(engine: check.bundledEngine, engineHash: String(repeating: "0", count: 64),
                                                           control: check.bundledControl, controlHash: FileDigest.sha256(check.bundledControl)!, owner: owner)
        let uninstall = Installer(deployment: d).uninstall
        let probe = """
        set -eu
        PATH=/usr/bin:/bin:/usr/sbin:/sbin
        root=\(q(d.directory))
        engine=\(q(d.enginePath))
        control=\(q(d.controlPath))
        engine_plist=\(q(d.enginePlistPath))
        control_plist=\(q(d.controlPlistPath))
        engine_job=\(q(d.engineJob))
        control_job=\(q(d.controlJob))
        engine_label=\(q(d.engineLabel))
        logs=\(q(d.logDirectory))
        client=\(q(base + "/client"))
        other=''
        elsewhere=''
        pass() { echo "PASS $1"; }
        failed() { echo "FAIL $1" >&2; exit 1; }
        loaded() { /bin/launchctl print "$1" >/dev/null 2>&1; }
        override() { /bin/launchctl print-disabled system | /usr/bin/awk -v label="\\"$1\\"" '$1 == label { print $3 }'; }
        engine_pid() { /bin/launchctl print "$engine_job" 2>/dev/null | /usr/bin/awk '$1 == "pid" { print $3; exit }'; }
        mode() { /usr/bin/stat -f '%u:%g:%Lp' "$1"; }
        as_owner() { /usr/bin/sudo -u '#\(owner)' -- "$client" "$@"; }
        install() { /bin/sh -c \(q(install)); }
        cleanup() {
          if [ -n "$other" ]; then /bin/kill -KILL "$other" 2>/dev/null || true; fi
          if [ -n "$elsewhere" ]; then /bin/rm -rf "$elsewhere"; fi
          /bin/rm -f "$root/ProbeClient"
          /bin/sh -c \(q(uninstall))
        }

        [ ! -e "$root" ] && [ ! -e "$engine_plist" ] && [ ! -e "$control_plist" ] && [ ! -e "$logs" ] || failed 'probe paths already exist'
        if loaded "$engine_job" || loaded "$control_job"; then failed 'probe jobs already loaded'; fi
        trap cleanup EXIT
        trap 'exit 1' HUP INT TERM

        if /bin/sh -c \(q(corrupt)) 2>/dev/null; then failed 'wrong checksum accepted'; fi
        [ ! -e "$engine" ] && [ ! -e "$engine_plist" ] && [ ! -e "$control_plist" ] || failed 'files left after a rejected install'
        pass 'wrong checksum rejected before anything is installed'

        /bin/mkdir -m 755 "$root"
        /bin/ln -s /usr/bin/true "$engine"
        if install 2>/dev/null; then failed 'symbolic-link destination accepted'; fi
        [ -L "$engine" ] || failed 'symbolic link replaced'
        /bin/rm "$engine"
        /bin/rmdir "$root"
        pass 'symbolic-link destination rejected'

        install
        [ "$(mode "$engine")" = 0:0:755 ] && [ "$(mode "$control")" = 0:0:755 ] || failed 'executables not root:wheel 0755'
        [ "$(mode "$engine_plist")" = 0:0:644 ] && [ "$(mode "$control_plist")" = 0:0:644 ] || failed 'definitions not root:wheel 0644'
        /usr/bin/codesign --verify --strict "$engine"
        loaded "$control_job" || failed 'controller not loaded'
        if loaded "$engine_job"; then failed 'fresh install started the engine'; fi
        [ "$(override "$engine_label")" = disabled ] || failed 'stopped engine would start at boot'
        pass 'fresh install: protected files, controller loaded, engine installed but off and disabled at boot'

        install
        if loaded "$engine_job"; then failed 'repeated install started the engine'; fi
        pass 'install is idempotent'

        /bin/cp "$client" "$root/ProbeClient"
        /bin/chmod 755 "$root/ProbeClient"
        if /usr/bin/sudo -u nobody -- "$root/ProbeClient" stop; then failed 'another account was accepted'; fi
        /bin/rm "$root/ProbeClient"
        as_owner invalid
        pass 'another account is rejected'

        as_owner start
        pid=$(engine_pid)
        [ -n "$pid" ] && [ "$(/bin/ps -p "$pid" -o uid= | /usr/bin/tr -d ' ')" = 0 ] || failed 'engine not running as root'
        [ "$(override "$engine_label")" = enabled ] || failed 'running engine would not start at boot'
        as_owner start
        [ "$(engine_pid)" = "$pid" ] || failed 'repeated start restarted the engine'
        pass "start by the normal account without a prompt: engine PID $pid runs as root, enabled at boot; repeated start keeps it"

        install
        [ "$(engine_pid)" = "$pid" ] || failed 'install with unchanged components restarted the engine'
        pass 'install with unchanged components keeps a running engine (no USB interruption)'

        /usr/libexec/PlistBuddy -c 'Set :ProcessType Background' "$engine_plist"
        install
        restarted=$(engine_pid)
        [ -n "$restarted" ] && [ "$restarted" != "$pid" ] || failed 'changed definition did not restart the engine'
        [ "$(/usr/libexec/PlistBuddy -c 'Print :ProcessType' "$engine_plist")" = Standard ] || failed 'definition not restored'
        pass 'a changed definition is restored and the running engine restarts, staying on'

        as_owner stop
        if loaded "$engine_job"; then failed 'stop left the engine loaded'; fi
        if /bin/kill -0 "$restarted" 2>/dev/null; then failed 'stop returned before the engine exited'; fi
        [ -f "$engine_plist" ] || failed 'stop removed the definition'
        [ "$(override "$engine_label")" = disabled ] || failed 'stopped engine would start at boot'
        as_owner stop
        pass 'stop unloads and waits for the engine, keeps its definition, disables it at boot; repeated stop succeeds'

        # Another installation: the same engine name at a different path.
        elsewhere=$(/usr/bin/mktemp -d /private/tmp/tetherline-probe.XXXXXX)
        /bin/cp "$engine" "$elsewhere/\(d.engineName)"
        "$elsewhere/\(d.engineName)" run >/dev/null 2>&1 &
        other=$!
        /bin/sleep 0.5
        result=$(as_owner start 2>&1) && failed 'start accepted while another engine runs'
        echo "$result" | /usr/bin/grep -q 'REJECTED start: conflict' || failed "unexpected start failure: $result"
        if loaded "$engine_job"; then failed 'engine loaded next to another engine'; fi
        # SIGKILL: a shell started through the administrator prompt ignores SIGTERM,
        # and background children inherit that.
        /bin/kill -KILL "$other"
        wait "$other" 2>/dev/null || true
        other=''
        /bin/rm -rf "$elsewhere"
        elsewhere=''
        pass 'start refuses while another engine runs'

        /bin/rm "$engine_plist"
        /bin/launchctl enable "$engine_job"
        install
        [ -f "$engine_plist" ] || failed 'definition not reinstalled'
        if loaded "$engine_job"; then failed 'migration started the engine'; fi
        [ "$(override "$engine_label")" = disabled ] || failed 'migrated engine would start at boot'
        pass 'the previous layout (definition removed while off) is migrated and stays off'

        /bin/sleep 2
        if /bin/launchctl print "$control_job" | /usr/bin/grep -q 'state = running'; then failed 'idle controller stayed running'; fi
        as_owner start
        as_owner stop
        pass 'the idle controller exits; launchd activates it again on demand'

        trap - EXIT HUP INT TERM
        cleanup
        [ ! -e "$root" ] && [ ! -e "$engine_plist" ] && [ ! -e "$control_plist" ] && [ ! -e "$logs" ] || failed 'uninstall left files'
        if loaded "$engine_job" || loaded "$control_job"; then failed 'uninstall left jobs loaded'; fi
        pass 'uninstall removes controller, engine, definitions, socket and logs'
        """
        var script = "set -eu\n/bin/sh -c \(q(probe))\n"
        if arguments.count > 3 {
            let bundle = arguments[3]
            let production = InstallationCheck(deployment: .production, bundledEngine: bundle + "/Contents/MacOS/muta",
                                               bundledControl: bundle + "/Contents/MacOS/TetherlineControl", owner: owner)
            script += "/bin/sh -c \(q(try production.installScript()))\necho 'PASS production installation converged'\n"
        }
        try script.write(toFile: output, atomically: true, encoding: .utf8)
        // For manual cleanup after an interrupted run.
        try ("set -eu\n" + uninstall).write(toFile: output + ".uninstall", atomically: true, encoding: .utf8)
    }
}
