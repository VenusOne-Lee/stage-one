import ArgumentParser
import Foundation

/// SO-131: `stage watchdog --pid <pid>` (hidden).
///
/// Stage One launches this from Contents/Helpers/stage at startup. It waits for the app's
/// process to exit, then brings back every window still listed in parked.json. After a
/// clean quit the app has already unparked everything and emptied the file, so this is a
/// no-op; after a crash or a `kill -9` it is what keeps windows from being stranded.
struct Watchdog: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watchdog",
        abstract: "Restore parked windows when Stage One exits.",
        shouldDisplay: false
    )

    @Option(help: "The Stage One process to watch.")
    var pid: Int32

    @Option(help: "Parked windows file (defaults to Stage One's parked.json).")
    var file: String?

    func run() throws {
        // Survive the signals that end the app from a terminal (Ctrl-C, closing the tab).
        signal(SIGINT, SIG_IGN)
        signal(SIGHUP, SIG_IGN)

        Self.waitForExit(of: pid)

        let url = file.map { URL(fileURLWithPath: $0) } ?? ParkedRestore.defaultFile
        let summary = ParkedRestore.restore(file: url)
        if !summary.isEmpty { FileHandle.standardError.write(Data((summary + "\n").utf8)) }
    }

    /// Blocks until `pid` exits (kqueue process source), or returns at once if it is gone.
    static func waitForExit(of pid: Int32) {
        let done = DispatchSemaphore(value: 0)
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global())
        source.setEventHandler { done.signal() }
        source.resume()
        // The process may have exited before the source was armed.
        if kill(pid, 0) != 0 && errno == ESRCH { done.signal() }
        done.wait()
        source.cancel()
    }
}
