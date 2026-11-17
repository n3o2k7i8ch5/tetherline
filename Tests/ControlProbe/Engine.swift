import Darwin

// Stand-in engine for the isolated root test. `run` only proves it runs as root
// and waits; `status` answers like an idle muta. No USB, routes, sockets or files.
let arguments = CommandLine.arguments
if arguments.count == 2 && arguments[1] == "status" {
    print("state waiting")
    exit(0)
}
guard arguments.count == 2 && arguments[1] == "run", geteuid() == 0 else { exit(78) }
while true { sleep(60) }
