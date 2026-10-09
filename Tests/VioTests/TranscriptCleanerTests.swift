import FoundationModels
import XCTest
@testable import Vio

struct FakeTranscriptGenerator: TranscriptGenerating {
    var availability: SystemLanguageModel.Availability = .available
    var action: @Sendable (String) async throws -> String

    func generate(_ transcript: String) async throws -> String {
        try await action(transcript)
    }
}

// Deliberately ignores task cancellation until the test releases it.
@MainActor
final class HeldGeneration {
    var continuation: CheckedContinuation<String, Never>?
    let started: XCTestExpectation
    let completed: XCTestExpectation

    init(started: XCTestExpectation, completed: XCTestExpectation) {
        self.started = started
        self.completed = completed
    }

    func generate() async -> String {
        let result = await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
        completed.fulfill()
        return result
    }

    func release(_ text: String) {
        continuation?.resume(returning: text)
        continuation = nil
    }
}

@MainActor
final class TranscriptCleanerTests: XCTestCase {
    func testSuccessfulCleanupTrimsOutputAndPassesOriginalInput() async {
        let cleaner = TranscriptCleaner(generator: FakeTranscriptGenerator { input in
            XCTAssertEqual(input, "um hello hello world")
            return "  Hello, world!\n"
        })
        let result = await cleaner.clean("um hello hello world", enabled: true)
        XCTAssertEqual(result, "Hello, world!")
    }

    func testDisabledAndEmptyTranscriptsBypassGeneration() async {
        let cleaner = TranscriptCleaner(generator: FakeTranscriptGenerator { _ in
            XCTFail("Generation should be bypassed")
            return "Unexpected"
        })
        let disabled = await cleaner.clean("original", enabled: false)
        let empty = await cleaner.clean(" \n", enabled: true)
        XCTAssertEqual(disabled, "original")
        XCTAssertEqual(empty, " \n")
    }

    func testUnavailableReasonsBypassGenerationAndHaveSettingsMessages() async {
        let reasons: [SystemLanguageModel.Availability.UnavailableReason] = [
            .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady,
        ]
        for reason in reasons {
            let availability = SystemLanguageModel.Availability.unavailable(reason)
            let cleaner = TranscriptCleaner(generator: FakeTranscriptGenerator(availability: availability) { _ in
                XCTFail("Unavailable model should be bypassed")
                return "Unexpected"
            })
            let result = await cleaner.clean("original", enabled: true)
            XCTAssertEqual(result, "original")
            XCTAssertNotNil(availability.cleanupUnavailableReason)
        }
        XCTAssertNil(SystemLanguageModel.Availability.available.cleanupUnavailableReason)
    }

    func testBlankOutputAndGenerationErrorsPreserveOriginal() async {
        enum Failure: Error { case generation }
        let actions: [@Sendable (String) async throws -> String] = [
            { _ in " \n\t" },
            { _ in throw Failure.generation },
            { _ in
                throw LanguageModelSession.GenerationError.exceededContextWindowSize(
                    .init(debugDescription: "Transcript exceeds context")
                )
            },
        ]
        for action in actions {
            let cleaner = TranscriptCleaner(generator: FakeTranscriptGenerator(action: action))
            let result = await cleaner.clean(" original ", enabled: true)
            XCTAssertEqual(result, " original ")
        }
    }

    func testDeadlineReturnsWithoutWaitingForCancellationAndIgnoresLateOutput() async {
        let started = expectation(description: "Generation started")
        let completed = expectation(description: "Late generation completed")
        let returned = expectation(description: "Deadline returned original")
        let held = HeldGeneration(started: started, completed: completed)
        let cleaner = TranscriptCleaner(
            generator: FakeTranscriptGenerator { _ in await held.generate() },
            timeout: .milliseconds(20)
        )
        let task = Task {
            let result = await cleaner.clean("original", enabled: true)
            XCTAssertEqual(result, "original")
            returned.fulfill()
        }
        await fulfillment(of: [started, returned], timeout: 1)
        held.release("late replacement")
        await fulfillment(of: [completed], timeout: 1)
        await task.value
    }

    func testCancellationReturnsOriginal() async {
        let started = expectation(description: "Generation started")
        let completed = expectation(description: "Generation released")
        let returned = expectation(description: "Cancellation returned")
        let held = HeldGeneration(started: started, completed: completed)
        let cleaner = TranscriptCleaner(generator: FakeTranscriptGenerator { _ in await held.generate() })
        let task = Task {
            let result = await cleaner.clean("original", enabled: true)
            XCTAssertEqual(result, "original")
            returned.fulfill()
        }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        await fulfillment(of: [returned], timeout: 1)
        held.release("late")
        await fulfillment(of: [completed], timeout: 1)
        await task.value
    }
}
