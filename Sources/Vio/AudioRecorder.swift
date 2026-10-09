import AVFoundation

enum RecorderError: LocalizedError {
    case noInputDevice
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone input is available (or access was denied)."
        case .startFailed(let detail):
            return detail
        }
    }
}

/// Buffers microphone audio as 16 kHz mono float samples for the speech engine.
final class AudioRecorder {
    /// Memory guard only (~38 MB of samples in 10 min); the engine handles
    /// any length by chunking.
    static let maxDuration: TimeInterval = 600

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private var completion: (([Float]) -> Void)?
    private var autoStop: DispatchWorkItem?
    private(set) var isRunning = false

    /// Starts recording. `completion` is invoked exactly once on the main
    /// thread, both for manual stops and the automatic duration cutoff.
    func start(completion: @escaping ([Float]) -> Void) throws {
        precondition(!isRunning)
        self.completion = completion
        samples.removeAll()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let outputFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: 16000,
                  channels: 1,
                  interleaved: false
              ),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw RecorderError.noInputDevice
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.convertAndAppend(buffer: buffer, converter: converter, to: outputFormat)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw RecorderError.startFailed(error.localizedDescription)
        }

        isRunning = true
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        autoStop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxDuration, execute: work)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        autoStop?.cancel()
        autoStop = nil

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        let captured = samples
        samples.removeAll()
        lock.unlock()

        let callback = completion
        completion = nil
        DispatchQueue.main.async { callback?(captured) }
    }

    private func convertAndAppend(buffer: AVAudioPCMBuffer, converter: AVAudioConverter, to format: AVAudioFormat) {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status == .haveData || status == .inputRanDry, converted.frameLength > 0,
              let channel = converted.floatChannelData?[0] else { return }

        let newSamples = UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))
        lock.lock()
        samples.append(contentsOf: newSamples)
        lock.unlock()
    }
}
