import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else { exit(2) }
let operation = CommandLine.arguments[1]
let path = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL.path
let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.standardizedFileURL.path == path }
if operation == "stop" {
    for app in apps {
        guard app.terminate() else { fputs("Murmur couldn't quit. Quit it before rebuilding.\n", stderr); exit(1) }
        let deadline = Date().addingTimeInterval(3)
        while !app.isTerminated && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        guard app.isTerminated else { fputs("Murmur is still running. Quit it before rebuilding.\n", stderr); exit(1) }
    }
} else if operation == "verify" {
    guard !apps.isEmpty else { fputs("Murmur did not launch.\n", stderr); exit(1) }
    print("Murmur app bundle is running (\(apps.count) instance).")
} else { exit(2) }
