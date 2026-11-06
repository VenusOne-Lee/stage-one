import AppIntents
import StageOneCore

/// SO-090: a group on the desk, for Shortcuts and Spotlight.
struct GroupEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Group")
    static let defaultQuery = GroupQuery()

    let id: UUID
    let name: String
    let windowCount: Int

    init(_ g: StageGroup) {
        id = g.id
        name = g.name
        windowCount = g.windowIDs.count
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(windowCount) windows")
    }
}

struct GroupQuery: EntityStringQuery {
    private func groups() async -> [StageGroup] {
        await MainActor.run { StageController.shared.desk.groups }
    }

    func entities(for identifiers: [UUID]) async throws -> [GroupEntity] {
        let all = await groups()
        return identifiers.compactMap { id in all.first { $0.id == id } }.map(GroupEntity.init)
    }

    func entities(matching string: String) async throws -> [GroupEntity] {
        let all = await groups()
        let q = string.trimmingCharacters(in: .whitespaces)
        return (q.isEmpty ? all : Fuzzy.rank(all, query: q, key: \.name)).map(GroupEntity.init)
    }

    func suggestedEntities() async throws -> [GroupEntity] {
        await groups().map(GroupEntity.init)
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
