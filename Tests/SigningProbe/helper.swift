import Darwin
// Only proves the launchd context. No USB, routes, sockets or filesystem writes.
guard geteuid() == 0 else { exit(78) }
while true { sleep(60) }

