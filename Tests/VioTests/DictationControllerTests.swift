import AppKit
import XCTest
@testable import Vio

@MainActor
final class DictationControllerTests: XCTestCase {
    private var previousCleanupPreference: Any?

    override func setUp() {
        super.setUp()
        previousCleanupPreference = UserDefaults.standard.object(forKey: "VioCleanupEnabled")
    }

    override func tearDown() {
        if let previousCleanupPreference {
            UserDefaults.standard.set(previousCleanupPreference, forKey: "VioCleanupEnabled")
        } else {
            UserDefaults.standard.removeObject(forKey: "VioCleanupEnabled")
        }
        super.tearDown()
    }

    func testCleanupRetainsTargetAndPreferenceSnapshotAndBlocksHotkeys() async {
        AppSettings.cleanupEnabled = true
        let target = AXUIElementCreateApplication(getpid())
        let started = expectation(description: "Cleanup started")
        let completed = expectation(description: "Cleanup completed")
        let delivered = expectation(description: "Delivered")
        let held = HeldGeneration(started: started, completed: completed)
        var deliveries: [String] = []
        var states: [DictationController.State] = []
        var hints: [String] = []
        let controller = DictationController(
            cleaner: TranscriptCleaner(generator: FakeTranscriptGenerator { _ in await held.generate() }),
            transcribe: { _ in "raw transcript" },
            paste: { text, destination in
                deliveries.append(text)
                XCTAssertTrue(destination === target)
                return true
            },
            showIndicator: { destination, hint in
                XCTAssertTrue(destination === target)
                hints.append(hint)
            },
            hideIndicator: {}
        )
        controller.onStateChange = { state in
            states.append(state)
            if state == .transcribing { AppSettings.cleanupEnabled = false }
            if state == .idle { delivered.fulfill() }
        }
        controller.onError = { _, _, _ in XCTFail("Cleanup should not show an alert") }
        controller.handleCapturedSamples(Array(repeating: 0, count: 1600), into: target)
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(controller.state, .cleaning)
        controller.press()
        controller.release()
        XCTAssertEqual(controller.state, .cleaning)
        held.release("Cleaned transcript.")
        await fulfillment(of: [completed, delivered], timeout: 1)
        XCTAssertEqual(deliveries, ["Cleaned transcript."])
        XCTAssertEqual(states, [.transcribing, .cleaning, .idle])
        XCTAssertEqual(hints, ["Cleaning up…"])
    }

    func testTimeoutPastesOriginalExactlyOnceAfterLateGeneration() async {
        AppSettings.cleanupEnabled = true
        let started = expectation(description: "Cleanup started")
        let completed = expectation(description: "Late cleanup completed")
        let delivered = expectation(description: "Delivered original")
        let held = HeldGeneration(started: started, completed: completed)
        var deliveries: [String] = []
        let controller = DictationController(
            cleaner: TranscriptCleaner(
                generator: FakeTranscriptGenerator { _ in await held.generate() },
                timeout: .milliseconds(20)
            ),
            transcribe: { _ in "original" },
            paste: { text, _ in deliveries.append(text); return true },
            showIndicator: { _, _ in },
            hideIndicator: {}
        )
        controller.onStateChange = { if $0 == .idle { delivered.fulfill() } }
        controller.onError = { _, _, _ in XCTFail("Fallback should be silent") }
        controller.handleCapturedSamples(Array(repeating: 0, count: 1600), into: nil)
        await fulfillment(of: [started, delivered], timeout: 1)
        XCTAssertEqual(deliveries, ["original"])
        held.release("late replacement")
        await fulfillment(of: [completed], timeout: 1)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(deliveries, ["original"])
        XCTAssertEqual(controller.state, .idle)
    }

    func testTranscriptionFailureStillReportsErrorWithoutPasting() async {
        enum Failure: Error { case transcription }
        let finished = expectation(description: "Returned to idle")
        var errors: [String] = []
        let controller = DictationController(
            transcribe: { _ in throw Failure.transcription },
            paste: { _, _ in XCTFail("Failed transcription cannot paste"); return true },
            showIndicator: { _, _ in },
            hideIndicator: {}
        )
        controller.onError = { title, _, _ in errors.append(title) }
        controller.onStateChange = { if $0 == .idle { finished.fulfill() } }
        controller.handleCapturedSamples(Array(repeating: 0, count: 1600), into: nil)
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(errors, ["Transcription failed"])
    }
}
