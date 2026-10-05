import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else { exit(2) }
let operation = CommandLine.arguments[1]
let paths = CommandLine.arguments.dropFirst(2).map { URL(fileURLWithPath: $0).standardizedFileURL.path }
let apps = NSWorkspace.shared.runningApplications.filter { app in
    guard let path = app.bundleURL?.standardizedFileURL.path else { return false }
    return paths.contains(path)
}
if operation == "stop" {
    for app in apps {
        guard app.terminate() else { fputs("Murmur couldn't quit. Quit it before rebuilding.\n", stderr); exit(1) }
        let deadline = Date().addingTimeInterval(3)
        while !app.isTerminated && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        guard app.isTerminated else { fputs("Murmur is still running. Quit it before rebuilding.\n", stderr); exit(1) }
    }
} else if operation == "verify" {
    guard apps.count == 1, apps.first?.bundleURL?.standardizedFileURL.path == paths.first else {
        fputs("Expected one Murmur instance at the requested path; found \(apps.count) across the known bundles.\n", stderr)
        exit(1)
    }
    print("Murmur app bundle is running (1 instance across the known bundles).")
} else { exit(2) }
