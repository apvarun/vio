import Foundation
import XCTest
@testable import Vio

final class SpeechEngineTests: XCTestCase {
    func testPreloadAndConcurrentTranscription() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        setenv("VIO_MODEL_PATH", root.appendingPathComponent("Resources/whistle.cact").path, 1)
        setenv("NEEDLE_TELEMETRY", "0", 1)
        setenv("DO_NOT_TRACK", "1", 1)
        let engine = SpeechEngine.shared
        let done = expectation(description: "Concurrent model access completes")
        done.expectedFulfillmentCount = 8
        let lock = NSLock()
        var failures: [String] = []
        for _ in 0..<8 {
            engine.preload()
            DispatchQueue.global().async {
                do {
                    _ = try engine.loadIfNeeded()
                    let text = try engine.transcribe([Float](repeating: 0, count: 16000))
                    if !text.isEmpty {
                        lock.lock()
                        failures.append("Silence produced text: \(text)")
                        lock.unlock()
                    }
                } catch {
                    lock.lock()
                    failures.append(error.localizedDescription)
                    lock.unlock()
                }
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 60)
        lock.lock()
        let result = failures
        lock.unlock()
        XCTAssertEqual(result, [])
    }
}
