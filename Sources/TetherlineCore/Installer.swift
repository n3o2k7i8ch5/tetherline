import Darwin
import Foundation

/// Root shell programs for the two operations that need the administrator prompt:
/// installing/updating and uninstalling. Everyday start and stop go through the
/// controller instead, without a shell.
///
/// Only compiled paths and values captured before the prompt (digests, UID) are
/// interpolated, always quoted. Nothing from the phone, `muta status` or the
/// control socket reaches a script.
struct Installer {
    let deployment: Deployment

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && $0.isASCII }
    }

    /// Brings the system to exactly the bundled state, changing only what differs.
    /// Running twice is a no-op. The engine keeps running unless the engine itself or
    /// its launchd definition changes; then it restarts. A stopped engine stays stopped.
    func install(engine: String, engineHash: String, control: String, controlHash: String, owner: uid_t) throws -> String {
        guard owner > 0, Self.isDigest(engineHash), Self.isDigest(controlHash) else {
            throw TetherlineError.message("Invalid installation parameters.")
        }
        let q = Self.quote
        let d = deployment
        func encoded(_ plist: [String: Any]) throws -> String {
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).base64EncodedString()
        }
        return preamble + """

        stage=$(/usr/bin/mktemp -d "$root/.stage.XXXXXX")
        stage_executable() {
          [ ! -L "$1" ] && [ -f "$1" ] || fail 'A bundled executable is not a regular file.'
          /bin/cp "$1" "$stage/$2"
          /usr/sbin/chown root:wheel "$stage/$2"
          /bin/chmod -N "$stage/$2"
          /bin/chmod 755 "$stage/$2"
          # The digest was captured before the prompt; the app may not change underneath.
          [ "$(/usr/bin/shasum -a 256 "$stage/$2" | /usr/bin/awk '{print $1}')" = "$3" ] || fail 'The app changed while waiting for approval. Try again.'
          /usr/bin/codesign --verify --strict --all-architectures "$stage/$2"
        }
        stage_plist() {
          /usr/bin/printf '%s' "$1" | /usr/bin/base64 -D > "$stage/$2"
          /usr/bin/plutil -lint -s "$stage/$2"
          /bin/chmod 644 "$stage/$2"
        }
        prepare_log() {
          secure_file_if_present "$1"
          /usr/bin/touch "$1"
          /usr/sbin/chown root:wheel "$1"
          /bin/chmod -N "$1"
          /bin/chmod 644 "$1"
        }
        same() { /usr/bin/cmp -s "$1" "$2"; }

        stage_executable \(q(engine)) engine \(q(engineHash.lowercased()))
        stage_executable \(q(control)) control \(q(controlHash.lowercased()))
        stage_plist \(q(try encoded(d.enginePlist))) engine.plist
        stage_plist \(q(try encoded(d.controlPlist(owner: owner)))) control.plist
        ensure_directory "$logs"
        prepare_log "$engine_log"
        prepare_log "$control_log"

        # Controller. Replacing it never interrupts the engine.
        if ! same "$stage/control" "$control" || ! same "$stage/control.plist" "$control_plist" || ! loaded "$control_job"; then
          stop_job "$control_job" "$control"
          /bin/mv -f "$stage/control" "$control"
          /bin/mv -f "$stage/control.plist" "$control_plist"
          remove_socket
          /bin/launchctl enable "$control_job"
          /bin/launchctl bootstrap system "$control_plist" || fail 'macOS could not load the Tetherline helper. Check background permission in System Settings.'
        fi

        # Engine and its launchd definition. Replacing either restarts a running engine.
        if ! same "$stage/engine" "$engine" || ! same "$stage/engine.plist" "$engine_plist"; then
          was_loaded=no
          if loaded "$engine_job"; then was_loaded=yes; fi
          stop_job "$engine_job" "$engine"
          /bin/mv -f "$stage/engine" "$engine"
          /bin/mv -f "$stage/engine.plist" "$engine_plist"
          if [ "$was_loaded" = yes ]; then
            /bin/launchctl enable "$engine_job"
            /bin/launchctl bootstrap system "$engine_plist" || fail 'macOS could not restart the service after the update. Turn tethering off and on.'
            attempt=0
            until /bin/launchctl print "$engine_job" | /usr/bin/awk '/^\\tstate = running$/ { found=1 } END { exit !found }'; do
              [ "$attempt" -lt 20 ] || fail 'The service was updated but did not start. Check its log, then turn tethering off and on.'
              /bin/sleep 0.25
              attempt=$((attempt + 1))
            done
          fi
        fi

        # A stopped engine must not start at the next boot until the user enables it.
        if ! loaded "$engine_job"; then /bin/launchctl disable "$engine_job"; fi
        """
    }

    /// Stops both jobs and removes every file the installer created. Unknown files
    /// stop the removal of their directory with an error instead of being deleted.
    var uninstall: String {
        let socketCleanup = deployment.engineSocket.map { path in
            """

            # muta's fixed status socket, only when no engine could still use it.
            if ! /usr/bin/pgrep -f \(Self.quote(ServiceState.enginePattern(deployment))) >/dev/null; then /bin/rm -f \(Self.quote(path)); fi
            """
        } ?? ""
        return preamble + """

        stop_job "$control_job" "$control"
        stop_job "$engine_job" "$engine"
        /bin/rm -f "$control" "$control_plist" "$engine" "$engine_plist"
        remove_socket
        if [ -e "$logs" ] || [ -L "$logs" ]; then
          secure_directory "$logs"
          for file in "$engine_log" "$control_log"; do
            secure_file_if_present "$file"
            /bin/rm -f "$file"
          done
          /bin/rmdir "$logs" || fail 'The log directory contains unknown files. They were left in place.'
        fi\(socketCleanup)
        /bin/rmdir "$root/.operation-lock"
        /bin/rmdir "$root" || fail 'The Tetherline directory contains unknown files. They were left in place.'
        """
    }

    private var preamble: String {
        let d = deployment
        let q = Self.quote
        func parent(_ path: String) -> String { q((path as NSString).deletingLastPathComponent) }
        return """
        set -eu
        PATH=/usr/bin:/bin:/usr/sbin:/sbin
        export PATH
        umask 077
        [ "$(/usr/bin/id -u)" = 0 ] || { echo 'Administrator approval is required.' >&2; exit 1; }
        root=\(q(d.directory))
        engine=\(q(d.enginePath))
        engine_plist=\(q(d.enginePlistPath))
        engine_job=\(q(d.engineJob))
        engine_log=\(q(d.engineLogPath))
        control=\(q(d.controlPath))
        control_plist=\(q(d.controlPlistPath))
        control_job=\(q(d.controlJob))
        control_log=\(q(d.controlLogPath))
        socket=\(q(d.socketPath))
        logs=\(q(d.logDirectory))
        fail() { echo "$1" >&2; exit 1; }
        no_acl() { [ "$(/bin/ls -lde "$1" | /usr/bin/wc -l | /usr/bin/tr -d ' ')" = 1 ]; }
        secure_directory() {
          [ ! -L "$1" ] && [ -d "$1" ] || fail "Unsafe directory: $1"
          [ "$(/usr/bin/stat -f %u "$1")" = 0 ] || fail "Directory is not owned by root: $1"
          mode=$(/usr/bin/stat -f %Lp "$1")
          [ $((0$mode & 022)) -eq 0 ] || fail "Directory is writable by another user: $1"
          no_acl "$1" || fail "Unexpected ACL on directory: $1"
        }
        ensure_directory() {
          if [ ! -e "$1" ] && [ ! -L "$1" ]; then
            /bin/mkdir -m 755 "$1"
            /usr/sbin/chown root:wheel "$1"
            /bin/chmod -N "$1"
          fi
          secure_directory "$1"
        }
        secure_file_if_present() {
          [ ! -L "$1" ] || fail "Refusing a symbolic link: $1"
          if [ -e "$1" ]; then
            [ -f "$1" ] && [ "$(/usr/bin/stat -f %l "$1")" = 1 ] || fail "Not a single regular file: $1"
            [ "$(/usr/bin/stat -f %u "$1")" = 0 ] || fail "File is not owned by root: $1"
            mode=$(/usr/bin/stat -f %Lp "$1")
            [ $((0$mode & 022)) -eq 0 ] || fail "File is writable by another user: $1"
            no_acl "$1" || fail "Unexpected ACL on file: $1"
          fi
        }
        secure_directory /Library
        secure_directory \(parent(d.directory))
        secure_directory \(q(d.launchDaemons))
        secure_directory \(parent(d.logDirectory))
        ensure_directory "$root"
        /bin/mkdir "$root/.operation-lock" 2>/dev/null || fail 'Another Tetherline operation is in progress.'
        stage=''
        cleanup() {
          if [ -n "$stage" ]; then /bin/rm -rf "$stage"; fi
          /bin/rmdir "$root/.operation-lock" 2>/dev/null || true
          /bin/rmdir "$root" 2>/dev/null || true
        }
        trap cleanup EXIT
        trap 'exit 1' HUP INT TERM
        for file in "$engine" "$engine_plist" "$control" "$control_plist"; do secure_file_if_present "$file"; done
        loaded() { /bin/launchctl print "$1" >/dev/null 2>&1; }
        process_running() {
          /bin/ps -axo command= | /usr/bin/awk -v program="$1" '$0 == program || index($0, program " ") == 1 { found=1 } END { exit !found }'
        }
        # Never touch a job that uses a Tetherline label for another program.
        check_owner() {
          if loaded "$1"; then
            program=$(/bin/launchctl print "$1" | /usr/bin/sed -n 's/^[[:space:]]*program = //p' | /usr/bin/head -n 1)
            [ "$program" = "$2" ] || fail 'A different service uses a Tetherline label. Stop it before continuing.'
          fi
        }
        check_owner "$engine_job" "$engine"
        check_owner "$control_job" "$control"
        # Unload a job and wait until launchd and the process are both gone.
        stop_job() {
          if loaded "$1"; then /bin/launchctl bootout "$1" 2>/dev/null || true; fi
          attempt=0
          while loaded "$1" || process_running "$2"; do
            [ "$attempt" -lt 40 ] || fail 'A Tetherline service is still stopping. Try again shortly.'
            /bin/sleep 0.25
            attempt=$((attempt + 1))
          done
        }
        # launchd recreates the socket; a leftover may only be removed if root owns it.
        remove_socket() {
          if [ -e "$socket" ] || [ -L "$socket" ]; then
            [ ! -L "$socket" ] && [ -S "$socket" ] && [ "$(/usr/bin/stat -f %u "$socket")" = 0 ] || fail 'Unsafe control socket.'
            /bin/rm "$socket"
          fi
        }
        """
    }
}
