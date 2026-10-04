import AppKit

if CommandLine.arguments.contains("--check-permission") {
    exit(Diagnostics.checkCapturePermission())
}

if CommandLine.arguments.contains("--self-test") {
    exit(Diagnostics.runTapSelfTest())
}

if let index = CommandLine.arguments.firstIndex(of: "--watch-sessions") {
    let seconds = Double(CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : "") ?? 15
    exit(Diagnostics.watchSessions(seconds: seconds))
}

if let index = CommandLine.arguments.firstIndex(of: "--probe-multi-output") {
    exit(Diagnostics.probeMultiOutput(arguments: Array(CommandLine.arguments[(index + 1)...])))
}

if CommandLine.arguments.contains("--measure-scan") {
    exit(Diagnostics.measureProcessScan())
}

if let index = CommandLine.arguments.firstIndex(of: "--measure-taps") {
    exit(Diagnostics.measureTapLoad(arguments: Array(CommandLine.arguments[(index + 1)...])))
}

if CommandLine.arguments.contains("--list-sessions") {
    Diagnostics.printAudioSessions()
    exit(EXIT_SUCCESS)
}

#if DEBUG
if let index = CommandLine.arguments.firstIndex(of: "--snapshot-about"), index + 1 < CommandLine.arguments.count {
    Diagnostics.snapshotAbout(to: CommandLine.arguments[index + 1], dark: CommandLine.arguments.contains("--dark"))
    exit(EXIT_SUCCESS)
}

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
