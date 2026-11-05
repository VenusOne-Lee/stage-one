import ArgumentParser
import Foundation
import StageOneCore

@main
struct Stage: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stage",
        abstract: "Control Stage One from the command line.",
        version: "0.1.0"
    )

    func run() throws {
        print("Stage One CLI 0.1.0. Commands arrive with SO-100.")
    }
}
