import ArgumentParser
import Foundation
import StageOneCore

/// The `stage` command-line tool. Add a command by writing a `ParsableCommand` in its own
/// file in Sources/stage and listing it in `subcommands`. With no subcommand it prints help.
@main
struct Stage: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stage",
        abstract: "Control Stage One from the command line.",
        version: "0.1.0",
        subcommands: [
            Watchdog.self,  // hidden: launched by the app (SO-131)
        ]
    )
}
