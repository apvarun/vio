import XCTest
@testable import Vio

final class AppSettingsTests: XCTestCase {
    func testCleanupDefaultsOffAndPersistsChanges() {
        let key = "VioCleanupEnabled"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertFalse(AppSettings.cleanupEnabled)
        AppSettings.cleanupEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
        XCTAssertTrue(AppSettings.cleanupEnabled)
        AppSettings.cleanupEnabled = false
        XCTAssertFalse(AppSettings.cleanupEnabled)
    }

    func testKeywordNormalization() {
        XCTAssertEqual(AppSettings.normalizedKeywords("  Vio, Cactus Compute\n\n Amsterdam , \t "),
                       "Vio\nCactus Compute\nAmsterdam")
        XCTAssertEqual(AppSettings.normalizedKeywords(" , \n\t"), "")
        XCTAssertEqual(AppSettings.normalizedKeywords("François,Łukasz"), "François\nŁukasz")
    }
}
