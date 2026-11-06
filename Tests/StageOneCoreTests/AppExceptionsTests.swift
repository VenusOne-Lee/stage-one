import XCTest
@testable import StageOneCore

/// SO-015: uncooperative apps.
final class AppExceptionsTests: XCTestCase {
    func testGameCategories() {
        XCTAssertTrue(Uncooperative.isGame(category: "public.app-category.games"))
        XCTAssertTrue(Uncooperative.isGame(category: "public.app-category.puzzle-games"))
        XCTAssertFalse(Uncooperative.isGame(category: "public.app-category.productivity"))
        XCTAssertFalse(Uncooperative.isGame(category: nil))
    }

    func testIgnoredMove() {
        let target = CGPoint(x: 3000, y: 2000)
        XCTAssertFalse(Uncooperative.ignoredMove(target: target, actual: CGRect(x: 2999, y: 1990, width: 800, height: 600)))
        XCTAssertTrue(Uncooperative.ignoredMove(target: target, actual: CGRect(x: 100, y: 100, width: 800, height: 600)))
    }

    func testFlagNeverOverridesTheUser() {
        var list = [AppException(bundleID: "com.example.chat", name: "Chat", reason: .user, floats: false)]
        XCTAssertFalse(Uncooperative.flag(&list, bundleID: "com.example.chat", name: "Chat", reason: .detected))
        XCTAssertEqual(list.count, 1)
        XCTAssertTrue(Uncooperative.flag(&list, bundleID: "com.example.game", name: "Game", reason: .game))
        XCTAssertEqual(Uncooperative.floating(list), ["com.example.game"])
    }
}
