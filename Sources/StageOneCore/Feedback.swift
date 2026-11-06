import Foundation

/// SO-135: feedback without telemetry. Builds a pre-filled GitHub "new issue" link; nothing
/// is sent until the person submits the issue themselves.
public enum Feedback {
    public static let repository = "VenusOne-Lee/stage-one"
    /// GitHub rejects very long links; the app list is cut to stay well under.
    public static let maxURLLength = 7000

    public static func body(appVersion: String, macOS: String, apps: [String]?) -> String {
        var lines = [
            "**What happened?**",
            "",
            "",
            "**What did you expect?**",
            "",
            "",
            "---",
            "Stage One \(appVersion) · macOS \(macOS)",
        ]
        if let apps {
            lines.append(apps.isEmpty ? "Open apps: none" : "Open apps: \(apps.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    /// The new-issue link. With `apps`, as many app names as fit are included; the rest are
    /// counted ("and 4 more").
    public static func issueURL(appVersion: String, macOS: String, apps: [String]?, title: String = "") -> URL {
        func make(_ list: [String]?) -> URL {
            var c = URLComponents(string: "https://github.com/\(repository)/issues/new")!
            c.queryItems = [
                URLQueryItem(name: "title", value: title),
                URLQueryItem(name: "labels", value: "feedback"),
                URLQueryItem(name: "body", value: body(appVersion: appVersion, macOS: macOS, apps: list)),
            ]
            return c.url!
        }
        guard var list = apps else { return make(nil) }
        list = list.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var url = make(list)
        var dropped = 0
        while url.absoluteString.count > maxURLLength, !list.isEmpty {
            list.removeLast()
            dropped += 1
            url = make(list + ["and \(dropped) more"])
        }
        return url
    }
}
