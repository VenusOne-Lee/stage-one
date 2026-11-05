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
        discussion: """
        Examples:
          stage list
          stage save "Deep work"
          stage restore deep
          stage group 2
          stage layout halves
          stage export "Deep work" ~/Desktop
        """,
        version: "0.1.0",
        subcommands: [
            List.self, Status.self, Save.self, Restore.self, GroupCommand.self, Layout.self,
            Rewind.self, Export.self, Import.self, Pause.self, Resume.self,
        ]
    )
}
