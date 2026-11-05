import AppKit
import Foundation

/// SO-131: every parked window comes back if Stage One quits or crashes.
///
/// 1. Clean quit: `applicationWillTerminate` calls `StageController.stop()`, which unparks all.
/// 2. SIGTERM / SIGINT / SIGHUP: handled on the main queue, unpark all, then `exit(0)`.
/// 3. Uncaught Objective-C exception on the main thread: best-effort unpark.
/// 4. Anything else (a Swift trap, `kill -9`, a hang killed by the system): the watchdog,
///    `Contents/Helpers/stage watchdog --pid <our pid>`, waits for this process to exit and
///    restores whatever is still listed in parked.json.
///
/// Call `CrashSafety.install()` once at launch.
@MainActor
enum CrashSafety {
    private static var signalSources: [DispatchSourceSignal] = []
    private static var watchdog: Process?

    static func install() {
        installSignalHandlers()
        NSSetUncaughtExceptionHandler(stageOneUncaughtException)
        launchWatchdog()
    }

    /// Unparks everything. Skipped when the controller never started, so a run without
    /// Accessibility access can't wipe records a previous crash left behind.
    static func restoreWindows() {
        guard StageController.shared.isRunning else { return }
        StageController.shared.stop()
    }

    private static func installSignalHandlers() {
        guard signalSources.isEmpty else { return }
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)  // let the dispatch source see it instead of the default action
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    CrashSafety.restoreWindows()
                    exit(0)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    /// Starts the bundled watchdog. Not found (for example under `swift run`): skipped.
    static func launchWatchdog() {
        guard watchdog == nil else { return }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/stage")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { return }
        let p = Process()
        p.executableURL = helper
        p.arguments = ["watchdog", "--pid", String(ProcessInfo.processInfo.processIdentifier)]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        do {
            try p.run()
            watchdog = p
        } catch {
            NSLog("Stage One: could not start the watchdog: \(error)")
        }
    }
}

/// C-compatible uncaught exception handler (no captures, not actor-isolated).
private func stageOneUncaughtException(_ exception: NSException) {
    guard Thread.isMainThread else { return }  // the watchdog covers other threads
    MainActor.assumeIsolated { CrashSafety.restoreWindows() }
}
