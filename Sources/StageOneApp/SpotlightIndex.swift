import AppKit
import Combine
import CoreSpotlight
import StageOneCore
import UniformTypeIdentifiers

/// SO-091: scenes in Spotlight. Each saved scene is indexed with Core Spotlight as
/// "Restore <name>", so typing part of its name finds it; opening the result restores it.
/// On macOS 26, Spotlight also lists the App Intents from SO-090 as actions (Tab fills in
/// the scene), which needs no code here beyond the intents and their metadata.
@MainActor
final class SpotlightIndex {
    static let shared = SpotlightIndex()
    static let domain = "africa.venusone.StageOne.scenes"
    static let prefix = "scene:"

    private var watch: AnyCancellable?
    private var indexed: [String] = []

    func install() {
        guard watch == nil, CSSearchableIndex.isIndexingAvailable() else { return }
        watch = SceneStore.shared.$scenes
            .map { $0.map(\.name).sorted() }
            .removeDuplicates()
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { _ in MainActor.assumeIsolated { SpotlightIndex.shared.reindex() } }
    }

    /// Replaces the index with the scenes on disk.
    func reindex() {
        let scenes = SceneStore.shared.scenes
        let names = scenes.map(\.name).sorted()
        guard names != indexed else { return }
        let removed = Set(indexed).subtracting(names).map { Self.prefix + $0 }
        indexed = names
        let items = scenes.map { s -> CSSearchableItem in
            let a = CSSearchableItemAttributeSet(contentType: .item)
            a.title = "Restore \(s.name)"
            a.displayName = "Restore \(s.name)"
            let groups = s.groups.filter { !$0.windows.isEmpty }.map(\.name)
            a.contentDescription = "Stage One scene: \(s.windowCount) windows in \(groups.joined(separator: ", "))"
            a.keywords = [s.name, "scene", "Stage One"] + groups
            a.lastUsedDate = s.savedAt
            return CSSearchableItem(uniqueIdentifier: Self.prefix + s.name, domainIdentifier: Self.domain, attributeSet: a)
        }
        let index = CSSearchableIndex.default()
        if !removed.isEmpty { index.deleteSearchableItems(withIdentifiers: removed) { _ in } }
        // Re-indexing an identifier replaces its item.
        index.indexSearchableItems(items) { error in
            if let error { NSLog("Stage One: Spotlight indexing failed: \(error)") }
        }
    }

    /// Opens a Spotlight result: restores the scene it names. Returns false for other activities.
    func open(_ activity: NSUserActivity) -> Bool {
        guard activity.activityType == CSSearchableItemActionType,
              let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              id.hasPrefix(Self.prefix) else { return false }
        let name = String(id.dropFirst(Self.prefix.count))
        SceneStore.shared.reload()
        guard let scene = SceneStore.shared.scenes.first(where: { $0.name == name }) else {
            Toast.shared.show("“\(name)” isn't saved any more")
            return true
        }
        guard StageController.shared.isRunning else {
            Toast.shared.show("Stage One is paused", detail: "Resume it to restore “\(name)”.")
            return true
        }
        SceneRestore.restore(scene)
        return true
    }
}
