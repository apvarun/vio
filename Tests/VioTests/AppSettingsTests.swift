import XCTest
@testable import Vio

final class AppSettingsTests: XCTestCase {
    func testKeywordNormalization() {
        XCTAssertEqual(AppSettings.normalizedKeywords("  Vio, Cactus Compute\n\n Amsterdam , \t "),
                       "Vio\nCactus Compute\nAmsterdam")
        XCTAssertEqual(AppSettings.normalizedKeywords(" , \n\t"), "")
        XCTAssertEqual(AppSettings.normalizedKeywords("François,Łukasz"), "François\nŁukasz")
    }
}
