import Foundation
import XCTest
@testable import Vio

final class WavReaderTests: XCTestCase {
    private func wav(samples: [Int16] = [16384, -16384], channels: UInt16 = 1,
                     rate: UInt32 = 16000, format: UInt16 = 1, extensiblePCM: Bool = true) -> Data {
        func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
            withUnsafeBytes(of: value.littleEndian) { Array($0) }
        }
        var fmt = le(format) + le(channels) + le(rate) + le(rate * UInt32(channels) * 2)
        fmt += le(channels * 2) + le(UInt16(16))
        if format == 0xFFFE {
            fmt += le(UInt16(22)) + le(UInt16(16)) + le(UInt32(0))
            fmt += [extensiblePCM ? 1 : 3, 0, 0, 0, 0, 0, 16, 0, 128, 0, 0, 170, 0, 56, 155, 113]
        }
        let audio = samples.flatMap { le($0) }
        let chunks = Array("fmt ".utf8) + le(UInt32(fmt.count)) + fmt
            + Array("data".utf8) + le(UInt32(audio.count)) + audio
        return Data(Array("RIFF".utf8) + le(UInt32(chunks.count + 4)) + Array("WAVE".utf8) + chunks)
    }

    func testPCMAndStereoDownmix() throws {
        XCTAssertEqual(try WavReader.mono16kSamples(from: wav()), [0.5, -0.5])
        XCTAssertEqual(try WavReader.mono16kSamples(from: wav(samples: [16384, -16384, 8192, 8192], channels: 2)), [0, 0.25])
    }

    func testResampling() throws {
        XCTAssertEqual(try WavReader.mono16kSamples(from: wav(samples: [0, 16384], rate: 8000)), [0, 0.25, 0.5, 0.5])
    }

    func testEmptyAudio() throws {
        XCTAssertEqual(try WavReader.mono16kSamples(from: wav(samples: [])), [])
    }

    func testRejectsEveryTruncation() {
        let valid = wav()
        for count in 0..<valid.count {
            XCTAssertThrowsError(try WavReader.mono16kSamples(from: Data(valid.prefix(count))), "Length \(count)")
        }
    }

    func testInvalidMetadata() {
        XCTAssertThrowsError(try WavReader.mono16kSamples(from: wav(channels: 0)))
        XCTAssertThrowsError(try WavReader.mono16kSamples(from: wav(rate: 0)))
        XCTAssertThrowsError(try WavReader.mono16kSamples(from: wav(samples: [1], channels: 2)))
        var shortFormat = wav()
        shortFormat.replaceSubrange(16..<20, with: [2, 0, 0, 0])
        XCTAssertThrowsError(try WavReader.mono16kSamples(from: shortFormat))
    }

    func testExtensibleFormatRequiresPCM() throws {
        XCTAssertEqual(try WavReader.mono16kSamples(from: wav(format: 0xFFFE)), [0.5, -0.5])
        XCTAssertThrowsError(try WavReader.mono16kSamples(from: wav(format: 0xFFFE, extensiblePCM: false)))
        XCTAssertThrowsError(try WavReader.mono16kSamples(from: wav(format: 3)))
    }

    func testSelftestPaths() {
        XCTAssertEqual(Selftest.inputURL(arguments: ["Vio", "--selftest", "clip.wav"])?.lastPathComponent, "clip.wav")
        XCTAssertEqual(Selftest.inputURL(arguments: ["Vio", "--selftest", "/tmp/clip.wav"])?.path, "/tmp/clip.wav")
        XCTAssertEqual(Selftest.inputURL(arguments: ["Vio", "--selftest", "~/clip.wav"])?.path,
                       ("~/clip.wav" as NSString).expandingTildeInPath)
        XCTAssertNil(Selftest.inputURL(arguments: ["Vio", "--selftest"]))
        XCTAssertNil(Selftest.inputURL(arguments: ["Vio", "--selftest", "--other"]))
    }
}
