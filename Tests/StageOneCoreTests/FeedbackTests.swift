import XCTest
@testable import StageOneCore

/// SO-135: telemetry-free feedback.
final class FeedbackTests: XCTestCase {
    private func body(of url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "body" }?.value
    }

    func testIssueLinkCarriesVersionsAndNoAppsWithoutConsent() {
        let url = Feedback.issueURL(appVersion: "0.1.0", macOS: "15.1", apps: nil)
        XCTAssertTrue(url.absoluteString.hasPrefix("https://github.com/VenusOne-Lee/stage-one/issues/new?"))
        let b = body(of: url) ?? ""
        XCTAssertTrue(b.contains("Stage One 0.1.0 · macOS 15.1"))
        XCTAssertFalse(b.contains("Open apps"))
    }

    func testAppsIncludedSortedWithConsent() {
        let b = body(of: Feedback.issueURL(appVersion: "0.1.0", macOS: "15.1", apps: ["Safari", "Mail", "Xcode"])) ?? ""
        XCTAssertTrue(b.contains("Open apps: Mail, Safari, Xcode"))
    }

    func testLongAppListIsCutToFit() {
        let apps = (0..<500).map { "Some Long Application Name \($0)" }
        let url = Feedback.issueURL(appVersion: "0.1.0", macOS: "15.1", apps: apps)
        XCTAssertLessThanOrEqual(url.absoluteString.count, Feedback.maxURLLength)
        XCTAssertTrue((body(of: url) ?? "").contains("more"))
    }
}
