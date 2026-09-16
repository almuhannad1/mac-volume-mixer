import AppKit

if CommandLine.arguments.contains("--self-test") {
    exit(Diagnostics.runTapSelfTest())
}

if CommandLine.arguments.contains("--list-sessions") {
    Diagnostics.printAudioSessions()
    exit(EXIT_SUCCESS)
}

#if DEBUG
if let index = CommandLine.arguments.firstIndex(of: "--snapshot-panel"), index + 1 < CommandLine.arguments.count {
    Diagnostics.snapshotPanel(to: CommandLine.arguments[index + 1], dark: CommandLine.arguments.contains("--dark"))
    exit(EXIT_SUCCESS)
}
#endif

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
