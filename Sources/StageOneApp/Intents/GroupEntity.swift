import AppIntents
import StageOneCore

/// SO-090: a group on the desk, for Shortcuts and Spotlight.
struct GroupEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Group")
    static let defaultQuery = GroupQuery()

    let id: UUID
    /// SO-122: properties later actions in a shortcut can read.
    @Property(title: "Name") var name: String
    @Property(title: "Windows") var windowCount: Int
    @Property(title: "On stage") var onStage: Bool

    init(_ g: StageGroup, onStage: Bool) {
        id = g.id
        name = g.name
        windowCount = g.windowIDs.count
        self.onStage = onStage
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(windowCount) windows")
    }
}

struct GroupQuery: EntityStringQuery {
    private func groups() async -> (all: [StageGroup], active: UUID?) {
        await MainActor.run { (StageController.shared.desk.groups, StageController.shared.desk.activeID) }
    }

    func entities(for identifiers: [UUID]) async throws -> [GroupEntity] {
        let (all, active) = await groups()
        return identifiers.compactMap { id in all.first { $0.id == id } }.map { GroupEntity($0, onStage: $0.id == active) }
    }

    func entities(matching string: String) async throws -> [GroupEntity] {
        let (all, active) = await groups()
        let q = string.trimmingCharacters(in: .whitespaces)
        return (q.isEmpty ? all : Fuzzy.rank(all, query: q, key: \.name)).map { GroupEntity($0, onStage: $0.id == active) }
    }

    func suggestedEntities() async throws -> [GroupEntity] {
        let (all, active) = await groups()
        return all.map { GroupEntity($0, onStage: $0.id == active) }
    }
}

/// SO-090: the layouts `Arrange` offers.
enum ArrangeLayout: String, AppEnum {
    case halves, focus, thirds, grid, free

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Layout")
    static let caseDisplayRepresentations: [ArrangeLayout: DisplayRepresentation] = [
        .halves: "Halves",
        .focus: "Main + side",
        .thirds: "Thirds",
        .grid: "Grid",
        .free: "Free",
    ]

    var kind: LayoutKind { LayoutKind(rawValue: rawValue) ?? .free }
}
